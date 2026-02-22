# Opencode zombie server problem

## Symptom

Every time Neovim restarts, `opencode.nvim` spawns a new `opencode --port`
process even if one is already running for the same directory. The old
processes are never killed. Over time they accumulate and eat RAM.

## Root cause

The duplication lives in opencode.nvim's provider layer, not in proj.

### How toggle() works

```
require("opencode").toggle()
  -> require("opencode.provider").toggle()
    -> require("opencode.provider.snacks"):toggle()
      -> require("snacks.terminal").toggle(self.cmd, self.opts)
```

`snacks.terminal` tracks open terminals **in memory** by command string.
When you call `toggle()`:

- If a terminal with that command already exists in memory -> show/hide it.
- If not -> spawn a new process.

### What happens on restart

1. Neovim exits. The snacks.terminal in-memory table is gone.
2. The `opencode --port` process **survives** -- it's a separate OS process
   that doesn't receive SIGHUP (or ignores it).
3. Neovim starts again. snacks.terminal has no memory of the old terminal.
4. User calls `toggle()`. snacks.terminal sees no existing terminal for
   `"opencode --port"`. It spawns a **new** process on a new random port.
5. The old process is still running. Now there are two.
6. Repeat on every restart.

### Why stop() doesn't help

`opencode.provider.snacks:stop()` closes the snacks terminal window but has
a TODO comment about stopping the underlying job. Even if the terminal
buffer is deleted, the opencode process may have already detached or simply
isn't killed by the buffer teardown.

`opencode.provider.init:stop()` calls `events.disconnect()` which only
stops the SSE subscription (a curl job), not the opencode server process.

### Why start() doesn't check

`opencode.provider.snacks:start()` does check `self:get()` which calls
`snacks.terminal.get(cmd, { create = false })`. But this only checks the
**in-memory** terminal list. It has no awareness of OS-level processes.

The server discovery module (`opencode.cli.server`) **can** find running
servers via `pgrep` + `lsof`, but `start()` and `toggle()` never call it.

## Where the fix belongs

This is an opencode.nvim bug. The fix should go in the provider layer:

**Before spawning**, check if a server already exists for the CWD:

```lua
-- In opencode/provider/snacks.lua:start()
function Snacks:start()
    if self:get() then
        return  -- terminal already exists in this nvim session
    end
    -- Check for orphaned servers from previous sessions
    local server = require("opencode.cli.server")
    server.get_all_servers_in_nvim_cwd():next(function(servers)
        if #servers > 0 then
            -- Reuse existing server, just open the terminal UI
            -- connected to its port instead of spawning new
            ...
        else
            require("snacks.terminal").open(self.cmd, self.opts)
        end
    end)
end
```

**On VimLeavePre**, optionally kill the server process if no other nvim
instances are connected to it.

## What proj does about it

proj ensures `tcd` is set to the project root before calling `toggle()`.
This is the extent of proj's responsibility -- CWD correctness. The process
lifecycle is opencode.nvim's domain.

## Workaround

Kill orphaned opencode servers manually:

```sh
pkill -f "opencode.*--port"
```

Or add to your shell rc / nvim config:

```lua
-- Kill existing opencode servers for this CWD before starting
vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        vim.fn.system("pkill -f 'opencode.*--port.*" .. vim.fn.getcwd() .. "'")
    end,
})
```
