# docs/assets/shell.png: the shell tuidev sets up (Starship, eza, ripgrep, delta). Render: make screenshots
Source docs/assets/tapes/theme.tape
Set Width 980
Set Height 940

Hide
Type "source docs/assets/tapes/demo-shell.sh && clear"
Enter
Sleep 2s
Show

Type "ll src"
Enter
Sleep 800ms
Type "rg --no-heading TODO"
Enter
Sleep 800ms
Type "git diff"
Enter
Sleep 1500ms
Screenshot docs/assets/shell.png
Sleep 500ms
