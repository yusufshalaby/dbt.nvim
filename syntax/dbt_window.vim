" dbt_window.vim - Syntax highlighting for the dbt.nvim dependency window

" Exit if syntax already loaded
if exists("b:current_syntax")
  finish
endif

" 1. Header Match
" Matches lines that start with "Parents" or "Children", followed by a count in parentheses.
" Pattern: ^(Parents|Children)\s*(\d+)\s*$
syn match dbtWindowHeader '^\(Parents\|Children\)\s*(\d\+)\s*$'

" 2. Model Line Match
" Matches the indented model lines using the connector character (e.g., '  ├╴ my_model').
" This is mainly to ensure the entire model line is not accidentally included in other syntax groups.
syn match dbtWindowModel '^\s*[└├]╴\s*.\+$'

" --- Highlight Links ---

" Link the header to a high-contrast group (like Title or Statement).
" Title is a standard choice for headings.
hi link dbtWindowHeader Title

" Link the model line text to a neutral color group (like Identifier or Normal).
hi link dbtWindowModel Identifier

" Set the current syntax name
let b:current_syntax = "dbt_window"
