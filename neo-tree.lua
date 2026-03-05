-- @@@neotree
-- @@@plugins.neotree
-- ///neotree

-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-tree/nvim-web-devicons',
    },
    cmd = 'Neotree',
    keys = {
      { '<leader>\\', '<cmd>Neotree toggle reveal left<cr>', desc = 'Neo-tree (filesystem)' },
    },
    opts = {
      sources = { 'filesystem', 'git_status', 'buffers' },
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_hidden = false,
        },
      },
      default_component_configs = {
        git_status = {
          symbols = {
            added = 'A',
            modified = 'M',
            deleted = '[*]',
            renamed = 'R',
            untracked = '-',
            ignored = 'I',
            unstaged = '✗',
            staged = '✓',
            conflict = '!',
          },
        },
      },
    },
  },
}
