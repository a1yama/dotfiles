 filetype plugin indent on

" Instal vim-plug
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

 call plug#begin()

" SETTINGS
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-characterize'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-obsession'
Plug 'tpope/vim-vinegar'
Plug 'tpope/vim-apathy'
Plug 'tpope/vim-haystack' " replaces completion algorithm
Plug 'hedrok/vim-plugin-ruscmd'
Plug 'michaeljsmith/vim-indent-object'
Plug 'djoshea/vim-autoread'
Plug 'machakann/vim-highlightedyank'
Plug 'haya14busa/is.vim'
Plug 'vim-scripts/AutoComplPop'
Plug 'powerman/vim-plugin-AnsiEsc'

" TOOLS
Plug 'KabbAmine/lazyList.vim'
Plug 'preservim/nerdtree' " :NERDTree
Plug 'kevinhwang91/rnvimr' " ranger
Plug 'will133/vim-dirdiff'
Plug 'tpope/vim-fugitive' " :G
Plug 'glts/vim-radical' " gA on number
Plug 'glts/vim-magnum' " ↑ req by vim-radical
Plug 'tpope/vim-speeddating' " <C-a> <C-x> on dates
Plug 'nvim-telescope/telescope.nvim'
Plug 'nvim-telescope/telescope-media-files.nvim'

" EDITING
Plug 'tpope/vim-surround'
Plug 'tpope/vim-abolish'
Plug 'vim-scripts/ReplaceWithRegister'  " grr
Plug 'tommcdo/vim-exchange'

" WRITING
Plug 'dbakker/vim-paragraph-motion'
Plug 'https://gitlab.com/hedrok/langtool-adoc-vim.git'
Plug 'junegunn/vim-peekaboo'
Plug 'vimwiki/vimwiki'
  
" IDE
Plug 'dense-analysis/ale'
Plug 'sheerun/vim-polyglot'
Plug 'tpope/vim-unimpaired'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-dadbod'
Plug 'tpope/vim-dotenv' " :Dotenv {file} to load .env
Plug 'tpope/vim-jdaddy' " json mappings: aj, gqaj, gwaj
Plug 'preservim/tagbar'
Plug 'bfrg/vim-c-cpp-modern'
Plug 'dart-lang/dart-vim-plugin'
Plug 'thosakwe/vim-flutter'

" Run :PlugInstall to install the plugin.

" gamedev
Plug 'habamax/vim-godot'

" complition
Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/nvim-cmp'
Plug 'honza/vim-snippets'
Plug 'SirVer/ultisnips'
Plug 'tpope/vim-endwise'

" folding
Plug 'Konfekt/FastFold'

" navigation
Plug 'justinmk/vim-sneak'
Plug 'easymotion/vim-easymotion'

Plug 'mhinz/vim-signify'

    " Server
Plug 'fatih/vim-go'
Plug 'rust-lang/rust.vim'
Plug 'vim-python/python-syntax'
Plug 'nvie/vim-flake8' " :PyFlake8

    " Frontend
Plug 'mattn/emmet-vim'
Plug 'pangloss/vim-javascript'
Plug 'othree/html5.vim'
Plug 'chrisbra/csv.vim'
Plug 'cakebaker/scss-syntax.vim'

    " Config scripts support
Plug 'LnL7/vim-nix'
Plug 'elkowar/yuck.vim'
Plug 'mboughaba/i3config.vim'
Plug 'chr4/nginx.vim'
Plug 'lifepillar/pgsql.vim'
Plug 'ekalinin/dockerfile.vim'
Plug 'jvirtanen/vim-hcl'
Plug 'stephpy/vim-yaml'
Plug 'wgwoods/vim-systemd-syntax'
Plug 'towolf/vim-helm'

"Visual
Plug 'dracula/vim'
Plug 'ryanoasis/vim-devicons'
    

" required for nvim
Plug 'nvim-lua/popup.nvim'
Plug 'nvim-lua/plenary.nvim'

call plug#end()            " required


" PLUGIN CONFIGS

" snippets
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"
let g:UltiSnipsEditSplit="vertical"

if has('macunix')
    let g:python3_host_prog = '/opt/homebrew/bin/python3'
endif

" NERDTREE
nnoremap <C-n> :NERDTreeToggle<CR>
nnoremap <C-f> :NERDTreeFind<CR>
nnoremap <A-n> :RnvimrToggle<CR>

" LEADER
let mapleader = ','
map <Leader> <Plug>(easymotion-prefix)
map <leader>f <Plug>(easymotion-s)
map <leader>e <Plug>(easymotion-f)
map Q gq

" Lazy List configs
nnoremap gli :LazyList
vnoremap gli :LazyList
let g:lazylist_omap = 'il'
let g:lazylist_maps = [
            \ 'gl',
            \ {
                \ 'l' : '',
                \ '*' : '* ',
                \ '-' : '- ',
                \ 't' : '- [ ] ',
            \ }
    \ ]

" Latex
let g:livepreview_previewer = 'zathura'

" Vimwiki
let g:vimwiki_key_mappings = { 'table_mappings': 0 }
let g:vimwiki_list = [
      \ {'path': '~/alchemy/manuscripts/wiki'},
      \ {'path': '~/alchemy/cyberspace/docs/wiki'},
      \ ]

" Key mappings for switching between wikis
nnoremap <Leader>ww :VimwikiIndex<CR>
nnoremap <Leader>ws :VimwikiUISelect<CR>

" Godot
func! GodotSettings() abort
    setlocal foldmethod=expr
    setlocal tabstop=4
    nnoremap <buffer> <F4> :GodotRunLast<CR>
    nnoremap <buffer> <F5> :GodotRun<CR>
    nnoremap <buffer> <F6> :GodotRunCurrent<CR>
    nnoremap <buffer> <F7> :GodotRunFZF<CR>
endfunc
augroup godot | au!
    au FileType gdscript call GodotSettings()
augroup end"
