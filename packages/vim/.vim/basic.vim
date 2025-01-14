" Some settings are provided with tpope/vim-sensible
" ==========================================================
" COMPATIBILITY SETTINGS
" ==========================================================
set shellslash          " Use forward slashes, even on Windows
set mouse=a             " Enable mouse support in all modes
set t_Co=256            " Use 256 colors
set nocompatible        " Use Vim defaults instead of Vi defaults
set encoding=utf8       " Use UTF-8 encoding
set belloff=all         " Disable all bell sounds

" ==========================================================
" FILETYPE AND PLUGIN SETTINGS
" ==========================================================
filetype plugin indent on " Enable filetype plugins and indentation

" ==========================================================
" COMPLETION SETTINGS
" ==========================================================
set completeopt=noinsert,menuone,noselect " Configure completion behavior
set complete+=kspell                     " Include spell checking in completion
set shortmess+=c                         " Avoid showing completion messages

" ==========================================================
" AUTO WRITING AND PERFORMANCE
" ==========================================================
set autowrite           " Automatically save before certain commands
set lazyredraw          " Redraw screen only when necessary
set hidden              " Allow switching buffers without saving

" ==========================================================
" TAB AND INDENTATION SETTINGS
" ==========================================================
set smartindent         " Enable smart indentation
set autoindent          " Copy indent from the current line when starting a new line
set smarttab            " Use shiftwidth for <Tab> and <Backspace> operations
" Other settings are provided with tpope/vim-sleuth

" ==========================================================
" SEARCH SETTINGS
" ==========================================================
set path+=**            " Search for files in the current directory and all subdirectories
set ignorecase          " Ignore case in search patterns
set smartcase           " Override ignorecase if pattern contains uppercase letters
set hlsearch            " Highlight search results
" Enable hidden files in netrw
let g:netrw_list_hide=netrw_gitignore#Hide()
let g:netrw_list_hide.=",,^\\..\\{1,2}$"

" ==========================================================
" REGEX SETTINGS
" ==========================================================
set magic               " Enable 'magic' mode for regex
set regexpengine=1      " Use the first regex engine

" ==========================================================
" BACKUP AND UNDO SETTINGS
" ==========================================================
set undofile            " Enable persistent undo
set undodir=~/.vim/undodir " Directory to store undo files

" ==========================================================
" IDE-LIKE FEATURES
" ==========================================================
syntax enable           " Enable syntax highlighting
set wildignore+=**/node_modules/**,**/.git/**,**/dist/**,**/build/** " Ignore common directories
set number              " Show line numbers
set relativenumber      " Show relative line numbers

" ==========================================================
" MATCHING SETTINGS
" ==========================================================
set matchpairs+=<:>     " Highlight matching pairs of characters, adding <:>
set showmatch           " Briefly jump to matching bracket when inserting a bracket
set matchtime=3         " Duration to show matching brackets (tenths of a second)

" ==========================================================
" VISUAL SETTINGS
" ==========================================================
set showcmd             " Show partial command in the last line of the screen
set laststatus=0        " Hide status line (0: never, 1: only with multiple windows, 2: always)
set statusline=%t[%{strlen(&fenc)?&fenc:'none'},%{&ff}]%h%m%r%y%=%c,%l/%L\ %P " Customize status line

" ==========================================================
" FOLDING SETTINGS
" ==========================================================
set foldenable
set foldmethod=syntax
set foldlevelstart=1
hi Folded ctermfg=5     " Set color for folded lines
hi Folded ctermbg=black " Set background color for folded lines
hi FoldColumn ctermfg=5 " Set color for fold column
hi FoldColumn ctermbg=black " Set background color for fold column

" ==========================================================
" TRUE COLOR SETTINGS
" Enable 24-bit true colors if your terminal supports it.
" ==========================================================
if (has("termguicolors"))
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
    set termguicolors
endif
