" Prevent x from overriding what's in the clipboard.
noremap x "_x
noremap X "_x

" Prevent selecting and pasting from overwriting what you originally copied.
xnoremap p pgvy

" Keep cursor at the bottom of the visual selection after you yank it.
vmap y ygv<Esc>

" Navigate around splits with a single key combo. <-- REPLACED WITH PLUGIN
" nnoremap <C-l> <C-w><C-l>
" nnoremap <C-h> <C-w><C-h>
" nnoremap <C-k> <C-w><C-k>
" nnoremap <C-j> <C-w><C-j>

" WRITING
set display=lastline
inoremap . .<C-g>u
inoremap ! !<C-g>u
inoremap ? ?<C-g>u
inoremap : :<C-g>u

