" dbt_window.vim - Syntax highlighting for the dbt.nvim dependency window

" Exit if syntax already loaded
if exists("b:current_syntax")
  finish
endif

syn match dbtWindowTitle '^Model:\s.*$'

syn match dbtWindowHeader '^\(Parents\|Children\)\s*(\d\+)\s*$'

syn match dbtWindowModel '^\s*[└├]╴\s*.\+$'

hi link dbtWindowTitle Title
hi link dbtWindowHeader Title
hi link dbtWindowModel Identifier

let b:current_syntax = "dbt_window"
