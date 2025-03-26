fun! s:DetectFennel()
    if getline(1) =~# '^#!.*/bin/env\s\+fennel\>'
        setfiletype fennel
    endif
endfun

autocmd BufRead,BufNewFile *.fnl,*.fnlm setlocal filetype=fennel
autocmd BufNewFile,BufRead * call s:DetectFennel()
