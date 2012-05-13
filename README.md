Steps to patch and rebuild ubic website:

1. hack on templates in `src/`
2. `make local`
3. open `index.html` in browser
4. goto 1 until done
5. `make`     # regenerate html with correct `<base>` tag
6. `git push`

Please don't commit changes after local build, only after complete `make` rebuild.
