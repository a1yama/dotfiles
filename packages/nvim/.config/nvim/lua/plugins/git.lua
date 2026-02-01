return {
  {
    'tpope/vim-fugitive',
  },
  { 'tpope/vim-rhubarb' }, -- open browser for git repo
  { 'akinsho/git-conflict.nvim', version = "*", config = true },
  {
    'kdheepak/lazygit.nvim',
    lazy = true,
    cmd = { 'LazyGit', 'LazyGitConfig', 'LazyGitCurrentFile', 'LazyGitFilter', 'LazyGitFilterCurrentFile' },
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = {
      { '<leader>g', '<cmd>LazyGit<cr>', desc = 'LazyGit' },
    },
  },
}
