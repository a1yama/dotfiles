"Code Setup
let g:vim_markdown_autowrite = 1
let g:vim_markdown_conceal = 2
let g:vim_markdown_conceal_code_blocks = 2
"let g:vim_markdown_fenced_languages = 1
set conceallevel=2
let g:tex_conceal = ""
let g:vim_markdown_math = 1

" Exit Vim if NERDTree is the only window remaining in the only tab.
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" LANGUAGE TOOLS
let g:languagetool_jar='$HOME/m/ingredients/languagetool/languagetool-commandline.jar'
let g:languagetool_lang='en'

autocmd BufReadPost *
  \ if line("'\"") > 1 && line("'\"") <= line("$") |
  \ exe "normal! g`\"" |
  \ endif

augroup autosourcing
  autocmd!
  autocmd BufWritePost .vimrc source %
augroup END

augroup AMOLED
	au!
	autocmd Colorscheme	*	highlight NonText cterm=NONE ctermbg=17 gui=NONE guibg=#000000
						\ |	highlight Normal cterm=NONE ctermbg=17 gui=NONE guibg=#000000
						\ |	highlight Visual cterm=NONE ctermbg=76 ctermfg=16 gui=NONE guibg=#500060
augroup END

" Auto-resize splits when Vim gets resized.
autocmd VimResized * wincmd =

" Update a buffer's contents on focus if it changed outside of Vim.
au FocusGained,BufEnter * :checktime

" Unset paste on InsertLeave.
autocmd InsertLeave * silent! set nopaste

" Make sure all types of requirements.txt files get syntax highlighting.
autocmd BufNewFile,BufRead requirements*.txt set ft=python

" Make sure .aliases, .bash_aliases and similar files get syntax highlighting.
autocmd BufNewFile,BufRead .*aliases* set ft=sh

" Make sure Kubernetes yaml files end up being set as helm files.
au BufNewFile,BufRead *.{yaml,yml} if getline(1) =~ '^apiVersion:' || getline(2) =~ '^apiVersion:' | setlocal filetype=helm | endif

" Ensure tabs don't get converted to spaces in Makefiles.
autocmd FileType make setlocal noexpandtab

" Ensure that :Reload-ing the file doesn't define redundant autocmds
" https://learnvimscriptthehardway.stevelosh.com/chapters/14.html
augroup standard_group
  autocmd!

  " Force some file types to be other file types
  autocmd BufRead,BufNewFile *.ejs,*.mustache setfiletype html
  autocmd BufRead,BufNewFile *.json setfiletype json
  autocmd BufRead,BufNewFile *.json.* setfiletype json

  " http://www.reddit.com/r/vim/comments/2x5yav/markdown_with_fenced_code_blocks_is_great/
  autocmd BufNewFile,BufReadPost *.md set filetype=markdown
  autocmd BufNewFile,BufReadPost *.dockerfile set filetype=Dockerfile
  autocmd BufNewFile,BufReadPost *.jenkinsfile set filetype=groovy

  " Resize splits in all tabs upon window resize
  " https://vi.stackexchange.com/a/206
  autocmd VimResized * Tabdo wincmd =

augroup END

let g:markdown_fenced_languages = ['css', 'erb=eruby', 'javascript', 'js=javascript', 'json=javascript', 'ruby', 'sass', 'xml', 'html']

set wildignore+=**/bower_components/**,**/node_modules/**,**/dist/**,**/bin/**,**/tmp/**


