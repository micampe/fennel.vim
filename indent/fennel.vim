" Vim filetype plugin file
" Language: FENNEL
" Maintainer: Calvin Rose
"
" Modified from vim-clojure-static
" https://github.com/guns/vim-clojure-static/blob/master/indent/clojure.vim
" This should eventually be replaced by a more standard and performant
" indenter.

if exists("b:did_indent")
	finish
endif
let b:did_indent = 1

let s:save_cpo = &cpo
set cpo&vim

setlocal noautoindent nosmartindent
setlocal softtabstop=2 shiftwidth=2 expandtab
setlocal indentkeys=!,o,O

if exists("*searchpairpos")

	if !exists('g:fennel_maxlines')
		let g:fennel_maxlines = 100
	endif

	if !exists('g:fennel_fuzzy_indent')
		let g:fennel_fuzzy_indent = 1
	endif

	if !exists('g:fennel_fuzzy_indent_patterns')
        let g:fennel_fuzzy_indent_patterns = ['^accumulate$', '^case\(-try\)\=$',
	      \ '^each$', '^fn$', '^for$', '^faccumulate$', '^fcollect$',
	      \ '^i\?collect$', '^global$', '^let', '^lambda$', '^local$',
	      \ '^macro', '^match\(-try\)\=$', '^while', '^var$',
	      \ '^with-'] " Any with-foo will indent like `do`
	endif

	if !exists('g:fennel_fuzzy_indent_blacklist')
		let g:fennel_fuzzy_indent_blacklist = []
	endif

	if !exists('g:fennel_fuzzy_indent_special_patterns')
		let g:fennel_fuzzy_indent_special_patterns = ['^do$']
	endif

	if !exists('g:fennel_special_indent_words')
		let g:fennel_special_indent_words = ''
	endif

	if !exists('g:fennel_align_multiline_strings')
		let g:fennel_align_multiline_strings = 0
	endif

	if !exists('g:fennel_align_subforms')
		let g:fennel_align_subforms = 0
	endif

	function! s:syn_id_name()
		return synIDattr(synID(line("."), col("."), 0), "name")
	endfunction

	function! s:ignored_region()
		if s:syn_id_name() =~? '\vstring|comment|character'
			return true
		elseif has('nvim')
			let captures = v:lua.vim.treesitter.get_captures_at_cursor()
			return index(captures, 'comment') >= 0 ||
						\ index(captures, 'string') >= 0
		else
			return false
		endif
	endfunction

	function! s:current_char()
		return getline('.')[col('.')-1]
	endfunction

	function! s:current_word()
		return getline('.')[col('.')-1 : searchpos('\v>', 'n', line('.'))[1]-2]
	endfunction

	function! s:is_paren()
		return s:current_char() =~# '\v[\(\)\[\]\{\}]' && !s:ignored_region()
	endfunction

	" Returns 1 if string matches a pattern in 'patterns', which may be a
	" list of patterns, or a comma-delimited string of implicitly anchored
	" patterns.
	function! s:match_one(patterns, string)
		let list = type(a:patterns) == type([])
		           \ ? a:patterns
		           \ : map(split(a:patterns, ','), '"^" . v:val . "$"')
		for pat in list
			if a:string =~# pat | return 1 | endif
		endfor
	endfunction

	function! s:match_pairs(open, close, stopat)
		" Stop only on vector and map [ resp. {. Ignore the ones in strings and
		" comments.
		if a:stopat == 0 && g:fennel_maxlines > 0
			let stopat = max([line(".") - g:fennel_maxlines, 0])
		else
			let stopat = a:stopat
		endif

		let pos = searchpairpos(a:open, '', a:close, 'bWn', "!s:is_paren()", stopat)
		return [pos[0], col(pos)]
	endfunction

	function! s:fennel_check_for_string_worker()
		" Check whether there is the last character of the previous line is
		" highlighted as a string. If so, we check whether it's a ". In this
		" case we have to check also the previous character. The " might be the
		" closing one. In case the we are still in the string, we search for the
		" opening ". If this is not found we take the indent of the line.
		let nb = prevnonblank(v:lnum - 1)

		if nb == 0
			return -1
		endif

		call cursor(nb, 0)
		call cursor(0, col("$") - 1)
		if s:syn_id_name() !~? "string"
			return -1
		endif

		" This will not work for a " in the first column...
		if s:current_char() == '"' || s:current_char() == '`'
			call cursor(0, col("$") - 2)
			if s:syn_id_name() !~? "string"
				return -1
			endif
			if s:current_char() != '\'
				return -1
			endif
			call cursor(0, col("$") - 1)
		endif

		let p = searchpos('\(^\|[^\\]\)\zs"\`', 'bW')

		if p != [0, 0]
			return p[1] - 1
		endif

		return indent(".")
	endfunction

	function! s:check_for_string()
		let pos = getpos('.')
		try
			let val = s:fennel_check_for_string_worker()
		finally
			call setpos('.', pos)
		endtry
		return val
	endfunction

	" Returns 1 for opening brackets, -1 for _anything else_.
	function! s:bracket_type(char)
		return stridx('([{', a:char) > -1 ? 1 : -1
	endfunction

	" Returns: [opening-bracket-lnum, indent]
	function! s:fennel_indent_pos()
		" Get rid of special case.
		if line(".") == 1
			return [0, 0]
		endif

		" We have to apply some heuristics here to figure out, whether to use
		" normal lisp indenting or not.
		let i = s:check_for_string()
		if i > -1
			return [0, i + !!g:fennel_align_multiline_strings]
		endif

		call cursor(0, 1)

		" Find the next enclosing [ or {. We can limit the second search
		" to the line, where the [ was found. If no [ was there this is
		" zero and we search for an enclosing {.
		let paren = s:match_pairs('(', ')', 0)
		let bracket = s:match_pairs('\[', '\]', paren[0])
		let curly = s:match_pairs('{', '}', bracket[0])

		" In case the curly brace is on a line later then the [ or - in
		" case they are on the same line - in a higher column, we take the
		" curly indent.
		if curly[0] > bracket[0] || curly[1] > bracket[1]
			if curly[0] > paren[0] || curly[1] > paren[1]
				return curly
			endif
		endif

		" If the curly was not chosen, we take the bracket indent - if
		" there was one.
		if bracket[0] > paren[0] || bracket[1] > paren[1]
			return bracket
		endif

		" There are neither { nor [ nor (, ie. we are at the toplevel.
		if paren == [0, 0]
			return paren
		endif

		" Now we have to reimplement lispindent. This is surprisingly easy, as
		" soon as one has access to syntax items.
		"
		" - Check whether we are in a special position after a word in
		"   g:fennel_special_indent_words. These are special cases.
		" - Get the next keyword after the (.
		" - If its first character is also a (, we have another sexp and align
		"   one column to the right of the unmatched (.
		" - In case it is in lispwords, we indent the next line to the column of
		"   the ( + sw.
		" - If not, we check whether it is last word in the line. In that case
		"   we again use ( + sw for indent.
		" - In any other case we use the column of the end of the word + 2.
		call cursor(paren)

		" In case we are at the last character, we use the paren position.
		if col("$") - 1 == paren[1]
			return paren
		endif

		" In case after the paren is a whitespace, we search for the next word.
		call cursor(0, col('.') + 1)
		if s:current_char() == ' '
			call search('\v\S', 'W')
		endif

		" If we moved to another line, there is no word after the (. We
		" use the ( position for indent.
		if line(".") > paren[0]
			return paren
		endif

		" We still have to check, whether the keyword starts with a (, [ or {.
		" In that case we use the ( position for indent.
		let w = s:current_word()
		if s:bracket_type(w[0]) == 1
			return paren
		endif

		let ww = w

		if &lispwords =~# '\V\<' . ww . '\>' || (
					\ g:fennel_fuzzy_indent
					\ && !s:match_one(g:fennel_fuzzy_indent_blacklist, ww)
					\ && s:match_one(g:fennel_fuzzy_indent_patterns, ww))
			" Disable fuzzy for exceptions like `do` if an expr is on the first line
			if !(s:match_one(g:fennel_fuzzy_indent_special_patterns, ww)
						\ && match(getline('.'), '\v<\w+', col('.') -1, 2) != -1)
				return [paren[0], paren[1] + &shiftwidth - 1]
			endif
		endif

		call search('\v\_s', 'cW')
		call search('\v\S', 'W')
		if paren[0] < line(".")
			return [paren[0], paren[1] + (g:fennel_align_subforms ? 0 : &shiftwidth - 1)]
		endif

		call search('\v\S', 'bW')
		return [line('.'), col('.') + 1]
	endfunction

	function! GetFennelIndent()
		let lnum = line('.')
		let orig_lnum = lnum
		let orig_col = col('.')
		let [opening_lnum, indent] = s:fennel_indent_pos()

		" Account for multibyte characters
		if opening_lnum > 0
			let indent -= indent - virtcol([opening_lnum, indent])
		endif

		" Return if there are no previous lines to inherit from
		if opening_lnum < 1 || opening_lnum >= lnum - 1
			call cursor(orig_lnum, orig_col)
			return indent
		endif

		let bracket_count = 0

		" Take the indent of the first previous non-white line that is
		" at the same sexp level. cf. src/misc1.c:get_lisp_indent()
		while 1
			let lnum = prevnonblank(lnum - 1)
			let col = 1

			if lnum <= opening_lnum
				break
			endif

			call cursor(lnum, col)

			" Handle bracket counting edge case
			if s:is_paren()
				let bracket_count += s:bracket_type(s:current_char())
			endif

			while 1
				if search('\v[(\[{}\])]', '', lnum) < 1
					break
				elseif !s:ignored_region()
					let bracket_count += s:bracket_type(s:current_char())
				endif
			endwhile

			if bracket_count == 0
				" Check if this is part of a multiline string
				call cursor(lnum, 1)
				if s:syn_id_name() !~? '\vString|Buffer'
					call cursor(orig_lnum, orig_col)
					return indent(lnum)
				endif
			endif
		endwhile

		call cursor(orig_lnum, orig_col)
		return indent
	endfunction

	setlocal indentexpr=GetFennelIndent()

else

	" In case we have searchpairpos not available we fall back to
	" normal lisp indenting.
	setlocal indentexpr=
	setlocal lisp
	let b:undo_indent .= '| setlocal lisp<'

endif

let &cpo = s:save_cpo
unlet! s:save_cpo
