" dbt_window.vim - Syntax highlighting for the dbt.nvim dependency window

" Exit if syntax already loaded
if exists("b:current_syntax")
  finish
endif

syn match dbtWindowTitle '^\(Model\|Seed\|Source\|Snapshot\):\s.*$'

syn match dbtWindowHeader '^\(Parents\|Children\|Columns\)\s*(\d\+)\s*$'

syn match dbtWindowItemName '^\s*[└├]╴\s*\zs[^[:space:]]\+'
syn match dbtWindowItemType '\s\+\zs\w\+\ze\s*$'

hi link dbtWindowTitle Title
hi link dbtWindowHeader Title
hi link dbtWindowItemName Identifier
hi link dbtWindowItemType Comment

let b:current_syntax = "dbt_window"
