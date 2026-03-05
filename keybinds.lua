-- @@@nvim.config.keymaps

-- @@@keymaps
-- /@@keymaps.arrows
-- /@@keymaps.run /@@keymaps.r
-- /@@keymaps.window -- /@@keymaps.w
-- /@@keymaps.treesitter -- /@@keymaps.t
-- /@@keymaps.config
-- /@@keymaps.files
-- /@@keymaps.session
-- /@@keymaps.oil /@@keymaps.o
-- /@@keymaps.LSP
-- /@@keymaps.list -- /@@keymaps.l
-- /@@keymaps.search -- /@@keymaps.s
-- /@@keymaps.git -- /@@keymaps.g
-- /@@keymaps.words
-- /@@keymaps.M2 -- /@@keymaps.m
-- /@@keymaps.proj -- /@@keymaps.p
-- /@@keymaps.test -- /@@keymaps.num


local function map(cmd, lhs, rhs, des, opts)
    local final_opts = vim.tbl_extend('force', { noremap = true, desc = des }, opts or {})
    vim.keymap.set(cmd, lhs, rhs, final_opts)
end

local function map_n(lhs, rhs, description, opts)
    map('n', lhs, rhs, description, opts)
end

local function map_t(lhs, rhs, description, opts)
    map('t', lhs, rhs, description, opts)
end

local function map_i(lhs, rhs, description, opts)
    map('i', lhs, rhs, description, opts)
end

local function map_nv(lhs, rhs, description, opts)
    map({ 'n', 'x' }, lhs, rhs, description, opts)
end

local function map_nt(lhs, rhs, description, opts)
    map({ 'n', 't' }, lhs, rhs, description, opts)
end

local function map_all(lhs, rhs, description, opts)
    map({ 'n', 'c', 'x', 'i', 't' }, lhs, rhs, description, opts)
end

local function exec_cmd(cmd)
    return '<cmd>' .. cmd .. '<cr>' 
end

local function map_word(lhs, word, no_space)
    local suffix = no_space and '' or ' '
    map_i(lhs, word .. suffix, 'Insert word: ' .. word)
    map_n(lhs, 'i' .. word .. suffix, 'Insert word: ' .. word)
end

local function exec(cmd, msgs)
    msgs = msgs or {}
    local msg_err = msgs.msg_err or ('Failed to execute command ' .. cmd)
    return function()
        local ok, err = pcall(function()
            vim.cmd(cmd)
        end)
        if not ok then
            vim.notify(msg_err .. ' (' .. tostring(err) .. ')', vim.log.levels.ERROR)
        elseif msgs.msg_ok then
            vim.notify(msgs.msg_ok, vim.log.levels.INFO)
        end
    end
end


local function pathesc(path)
    return vim.fn.fnameescape(path)
end

local function config_file(relative)
    return relative and vim.fn.stdpath('config') .. '/' .. relative or vim.fn.stdpath('config')
end

local function open_dir(dir)
    return exec_cmd('e ' .. pathesc(dir))
end

local function open_config(file)
    return open_dir(config_file(file))
end



local function L(s)
    return '<leader>' .. s
end

local function LL(s)
    return '\\\\' .. s
end

local Ke = '<kEnter>'

map_n('<Esc><Esc>', '<Esc><Esc>' .. exec_cmd('nohlsearch'), '', { noremap = false })
map_t('<Esc><Esc>', '<C-\\><C-n>', 'Exit terminal mode', { noremap = false })
map_n(L '<BS><BS>', exec_cmd 'bd!', 'Delete all buffers')
map_nv('<C-S-8>', '#', 'Star backs', { noremap = false })


-- @@@keymaps.arrows

map_n('<Left>', '<C-w>h', 'Switch to left window')
map_n('<Right>', '<C-w>l', 'Switch to right window')
map_n('<Up>', '<C-w>k', 'Switch to upper window')
map_n('<Down>', '<C-w>j', 'Switch to down window')


map_nv('<C-Left>', '<C-w>H', 'Switch to left window')
map_nv('<C-Right>', '<C-w>L', 'Switch to right window')
map_nv('<C-Up>', '<C-w>K', 'Switch to upper window')
map_nv('<C-Down>', '<C-w>J', 'Switch to down window')


map_n('<S-Left>', '[b', 'Next buffer')
map_n('<S-Right>', ']b', 'Previous buffer')


map_n(L'<CR><CR>', exec_cmd 'e!', 'Refresh buffer')

-- @@@keymaps.run
-- @@@keymaps.r


map_n(L 'rr', exec('source %', {msg_ok = 'File reloaded'}), '[R]un')

map_n(L 'rp', function()
        local filetype = vim.bo.filetype
        local commands = {
            typst = 'TypstPreview',
            tex = 'LaTeXPreview',
            markdown = 'MarkdownPreview',
        }
        local cmd = commands[filetype]

        if not cmd then
            vim.notify('No run command defined for filetype: ' .. filetype, vim.log.levels.WARN)
            return
        end

        local ok, err = pcall(function()
            vim.cmd(cmd)
        end)

        if not ok then
            vim.notify('Failed to show preview of file (' .. tostring(err) .. ')', vim.log.levels.ERROR)
        end
    end,
    '[R]un [P]review')

map_n(L 'rl', function()
        vim.cmd('source ' .. config_file 'init.lua')
        vim.notify('Config reloaded', vim.log.levels.INFO)
    end,
    'Reload plugins')

-- @@@keymaps.window
-- @@@keymaps.w

map_n(L 'wv', '<C-w>v', 'Splits [W]indow [V]ertically')
map_nv(L 'wt', exec 'tab :split', 'Duplicates [W]indow new [T]ab')
map_nv(L 'w]', '<C-w>v<C-]>', 'Jumps to the tag in [W]indow')
map_nv(L 'wh', exec 'vert help', 'Jumps to the tag in [W]indow')
map_nv(L 'w=', '<C-w>=', '[Window Size Equalize [=]')
map_nv(L 'w+', exec 'resize +10', '[W]indow Size [+]10')
map_nv(L 'w-', exec 'resize -10', '[W]indow Size [-]10')
map_nv(L 'wT', '<C-w>v<C-]><C-w>Tgt<End>gT', 'Opens tag [W]indow in new [T]ab')
map_nv(L 'ws', '<C-w>s', '[S]plits window horisontally')


-- @@@keymaps.treesitter
-- @@@keymaps.t

map_nv(L 'tu', exec 'TSUpdate', '[T]ree-sitter: [U]pdate')
map_nv(L 'tt', exec 'InspectTree', '[T]ree-sitter: Inspect [T]ree')
map_nv(L 'ti', exec 'Inspect', '[T]ree-sitter: [I]nspect Word Under Cursor')


-- @@@keymaps.config
-- @@@keymaps.c

map_n(L 'ck', open_config 'lua/config/keybinds.lua', '[C]onfig: [k]eybinds.lua file')
map_n(L 'cl', open_config 'lua/config/lsp.lua', '[C]onfig: [l]sp.lua file')
map_n(L 'ci', open_config 'init.lua', '[C]onfig: [i]nit.lua file')
map_n(L 'co', open_config 'lua/config/options.lua', '[C]onfig: [o]ptions.lua file')
map_n(L 'ca', open_dir '~/.config/opencode/opencode.json', '[C]onfig: [O]pencode.json')
map_n(L 'cc', open_config 'lua/config/user_cmd.lua', '[C]onfig: user [C]md condig file')
map_n(L 'ch', open_dir '~/.config/hypr/', '[C]onfig: [H]yprland')


-- @@@keymaps.files
-- @@@keymaps.f

map_n(L 'fn', exec('e ' .. pathesc '~/docs_notes/notes/notes.typ'), '[F]iles: [N]otes')
map_n(L 'ft', exec('e ' .. pathesc '~/docs_notes/notes/todo.typ'), '[F]iles: [T]ODO')
map_n(L 'fmb', exec('e ' .. pathesc '~/docs_notes/notes/m2/bugs.typ'), '[F]iles: m2 [B]ugs')
map_n(L 'fmn', exec('e ' .. pathesc '~/docs_notes/notes/m2/notes.typ'), '[F]iles: m2 [N]otes')
map_n(L 'fi', exec('e ' .. pathesc '~/docs_notes/notes/icons.lua'), '[F]iles: [N]otes')


-- @@@keymaps.session

map_all('<End>', exec_cmd 'SoftW' .. exec_cmd 'q!', 'Save and Quit Window')
map_all('<End><End>', exec_cmd 'SoftW' .. exec_cmd 'bd!', 'Save and Quit Window')
map_all('<C-End>', exec_cmd 'SoftWA' .. exec_cmd 'SaveSession' .. exec_cmd 'qa!', 'Save and Quit Window')
map_all('<M-s>', exec_cmd 'SoftWA', '[S]ave All Files')
map_all('<M-S>', exec_cmd 'SoftWA' .. exec_cmd 'SaveSession', '[S]ave All Files and Session')
map_all('<Home>', exec_cmd 'LoadLastSession', 'Load Last Session')
map_all('<M-End>', exec_cmd 'SoftWA' .. exec_cmd 'qa!', 'Save and Quit Window, drop session')


-- /@@keymaps.LSP
-- /@@keymaps.l

-- map_nv(L'ld', vim.lsp.buf.definition, '[L]SP: Go to [D]efinition')
-- map_nv(L'lt', vim.lsp.buf.type_definition, '[L]SP: Go to [T]ype Definition')
-- map_nv(L'li', vim.lsp.buf.implementation, '[L]SP: Go to [I]mplementation')
-- map_nv(L'ln', vim.lsp.buf.rename, '[L]SP: Re[N]ame')
-- map_nv(L'la', vim.lsp.buf.code_action, '[L]SP: [A]ction')
-- map_nv(L'lr', vim.lsp.buf.references, '[L]SP: [R]eferences')
-- map_nv(L'lf', vim.lsp.buf.format, '[L]SP: [F]ormat Document')
-- map_nv(L'lh', vim.lsp.buf.hover, '[L]SP: [H]over Documentation')
-- map_nv(L'ls', vim.lsp.buf.signature_help, '[L]SP: [S]ignature Help')


-- @@@keymaps.a
-- /@@keymaps.ai
-- /@@keymaps.opencode
local opencode = require("opencode")
local ask_this = function() opencode.ask("@this: ", { submit = true }) end
local operator = function() return opencode.operator("@this ") end

map_nv(L 'aa', ask_this, "OpenCode: [A]sk")
map_nv(L 'as', opencode.select, "OpenCode: [S]elect")
map_nv(L 'ar', opencode.select_server, "OpenCode: Select se[R]ver")
map_nv(L 'ae', opencode.select_session, "OpenCode: Select s[E]ssion")
map_nv(L 'al', opencode.statusline, "OpenCode: Status [L]ine")

map_nt('<C-a>', function() require("opencode").toggle() end, "Toggle opencode")
map_n(L 'at', function() require("opencode").toggle() end, "Toggle opencode (also C-a)")
map_nv("go", operator, "Add range to opencode", { expr = true })
map_n("goo", operator, "Add line to opencode", { expr = true })

map_n("<S-C-u>", function() opencode.command("session.half.page.up") end, "Scroll opencode up")
map_n("<S-C-d>", function() opencode.command("session.half.page.down") end, "Scroll opencode down")

-- @@@keymaps.oil
-- @@@keymaps.o


map_nv(L'oo', exec('Oil'), '[O]il: current file directory')
map_nv(L'ooo', exec 'Oil lua vim.fn.getcwd()', '[O]il: current directory ([P]wd)')
map_nv(L'oc', exec('Oil ' .. config_file 'lua/config'), '[O]il: Nvim [C]onfig files')
map_nv(L'oi', exec('Oil ' .. config_file ''), '[O]il: Nvim [C]onfig init dir')
map_nv(L'op', exec('Oil ' .. config_file 'lua/config/plugins'), '[O]il: Nvim [P]lugin config files')
map_nv(L'om', exec('Oil ' .. pathesc '~/nvim-plugins'), '[O]il: [M]y nvim plugins')
map_nv(L'of', exec('Oil ' .. config_file 'ftplugin'), '[O]il: Nvim [F]iletypes')
map_nv(L'ol', exec('Oil ' .. config_file 'lsp'), '[O]il: Nvim [L]SP clients')
map_nv(L'oh', exec('Oil ' .. pathesc '~/.config/hypr'), '[O]il: [H]yprland')
map_nv(L'oa', exec('Oil ' .. pathesc '~/.config/opencode'), '[O]il: [A]ll')


-- @@@keymaps.telescope
-- @@@keymaps.search
-- @@@keymaps.s

local builtin = require 'telescope.builtin'

map_n(L 'sh', builtin.help_tags, '[S]earch [H]elp')
map_n(L 'sf', builtin.find_files, '[S]earch [F]iles')
map_n(L 'ss', builtin.symbols, '[S]earch [S]ymbols')
map_n(L 'sg', builtin.live_grep, '[S]earch by [G]rep')
map_n(L 's.', builtin.oldfiles, '[S]earch Recent Files ("." for repeat)')


-- map_n(L'sp', builtin.git_files, '[S]earch git [P]roject files')

map_n(L '/', function()
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        winblend = 10,
        previewer = false })
end, '[/] Fuzzily search in current buffer')

map_n(L 's/', function()
    builtin.live_grep {
        prompt_title = 'Live Grep in Open Files' }
end, '[S]earch [/] in Open Files')

map_n(L 'sn', function()
    builtin.find_files {
        cwd = config_file 'lua/config' }
end, '[S]earch [N]eovim files')

map_n(L 'sp', function()
    builtin.find_files {
        cwd = config_file 'lua/config/plugins' }
end, '[S]earch [P]lugins configs')

map_n(L 'sl', function()
    builtin.find_files {
        cwd = config_file 'lsp' }
end, '[S]earch [L]SP config lua files')

map_n(L 'st', function()
    builtin.find_files {
        cwd = config_file 'ftplugin' }
end, '[S]earch file[t]ypes configs')


-- @@@keymaps.list
-- @@@keymaps.l

map_nv(L 'lk', builtin.keymaps, 'List [K]eymaps')
map_nv(L 'lb', builtin.buffers, 'List [B]uffers')

map_nv(L 'lc', builtin.highlights, 'List [H]ighlight groups')
map_nv(L 'lcc', require('config.picker_exclusions').show_colorscheme_picker, 'List color[S]cheme (C-Minus to exclude)')
map_nv(L 'la', builtin.autocommands, 'List [A]utocommands')
map_nv(L 'lu', builtin.commands, 'List [U]ser commands')
map_nv(L 'lj', builtin.jumplist, 'List [J]umps')
map_nv(L 'lm', builtin.marks, 'List [M]arks')
map_nv(L 'lf', builtin.find_files, 'List [F]iles')
map_nv(L 'ltt', builtin.builtin, 'List [T]elescope builtins')

-- @@@keymaps.list.tags
map_nv(L 'lt', exec_cmd 'FTagsList', 'List [T]ags: [C]tags')
map_nv(L 'lts', builtin.tagstack, 'List [T]ags: [S]tack')
map_nv(L 'lh', builtin.help_tags, 'List [T]ags: [H]elptags')



-- @@@keymaps.words



map_word('<M-f>', 'false')
map_word('<M-t>', 'true')
map_word('<M-m>', '-- @@@', true)
map_word('<M-r>', '-- |||', true)


local git = require 'config.git_actions'

-- @@@keymaps.g
-- @@@keymaps.git
map_n(L 'gc', git.commit, '[G]it: Commit')
map_n(L 'gs', git.stash, '[G]it: Stash')
map_n(L 'gb', git.new_branch, '[G]it: New branch')
map_n(L 'gA', git.add_current_file, '[G]it: Add current file')
map_n(L 'ga', git.add_all, '[G]it: Add all files')
map_n(L 'gp', git.push, '[G]it: Push')



-- @@@keymaps.proj
-- @@@keymaps.p
-- /@@proj

map_nv(Ke .. 's', exec_cmd 'ProjectSwitch', '[S]witch project')
map_nv(Ke .. 'a', exec_cmd 'ProjectAdd', '[A]dd project')

map_nv(Ke .. 't', exec_cmd 'ProjectTodo', '[T]odo list')
map_nv(Ke .. 'b', exec_cmd 'ProjectBugs', '[B]ugs list')
map_nv(Ke .. 'd', exec_cmd 'ProjectTotest', 'Tot[e]st list')

map_nv(Ke .. '+t', exec_cmd 'ProjectAddTodo', 'Add [t]odo')
map_nv(Ke .. '+b', exec_cmd 'ProjectAddBug', 'Add [b]ug')
map_nv(Ke .. '+d', exec_cmd 'ProjectAddTotest', 'Add tot[e]st')

map_nv(Ke .. Ke .. 't', exec_cmd 'ProjectGlobalTodo', '[G]lobal [t]odo')
map_nv(Ke .. Ke .. 'k', exec_cmd 'ProjectGlobalKeymaps', '[G]lobal [k]eymaps')
map_nv(Ke .. Ke .. 'r', exec_cmd 'ProjectGlobalRemember', '[G]lobal [R]emember')

map_nv(Ke .. Ke .. '+t', exec_cmd 'ProjectGlobalAddTodo', '[G]lobal add [T]odo')
map_nv(Ke .. Ke .. '+k', exec_cmd 'ProjectGlobalAddKeymaps', '[G]lobal add [K]eymaps')
map_nv(Ke .. Ke .. '+r', exec_cmd 'ProjectGlobalAddRemember', '[G]lobal add [R]emember')

-- @@@keymaps.test
-- @@@keymaps.num
local Snacks = require 'snacks'
map_nv(L'1', function() Snacks.scratch() end, '[T]est 1')
map_nv(L'2', function() Snacks.scratch.select() end, '[T]est 2')
map_nv(L'3', function() Snacks.picker.grep() end, '[T]est 3')
map_nv(L'4', function() Snacks.picker.projects() end, '[T]est 4')
map_nv(L'5', function() Snacks.picker.explorer() end, '[T]est 5')
map_nv(L'6', function() Snacks.picker.highlights() end, '[T]est 6')
map_nv(L'7', function() Snacks.picker.lazy() end, '[T]est 7')
map_nv(L'8', function() Snacks.picker.pickers() end, '[T]est 8')
map_nv(L'9', function() Snacks.picker.icons() end, '[T]est 9')
map_nv(L'0', function() Snacks.explorer() end, '[T]est 0')


-- @@@keymaps.local

map_n(LL 'zz', function() Snacks.toggle.zen() end, '[Z]en Mode')
map_n(LL 'z+', function() Snacks.zen.zoom() end, '[Z]en Zoom')
-- Export mapping functions for use in other config files
return {
    map = map,
    map_n = map_n,
    map_t = map_t,
    map_i = map_i,
    map_nv = map_nv,
    map_nt = map_nt,
    map_all = map_all,
    exec_cmd = exec_cmd,
    L = L,
}
