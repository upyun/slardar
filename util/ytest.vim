" Vim syntax file
" Language:     ytest
" Maintainer:   Jing Ye <yejingx@gmail.com>
" Last Change:  2015 Oct 8
" Credits:      yejingx <yejingx@gmail.com>


syn match   ytestComment    "#.*$"
syn match   ytestCase       "===.*$"
syn match   ytestBlock      "---.*$"

hi def link ytestComment         Include
hi def link ytestCase            Todo
hi def link ytestBlock           Statement
