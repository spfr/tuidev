# docs/assets/cli.gif: the shipped zsh and the tools it wires in, in the demo
# repo: autosuggestions and syntax highlighting, zoxide's `z`, eza's tree, bat
# behind `cat`, fzf's Ctrl-T with a bat preview, atuin's Ctrl-R, and tokei.
# Render: make screenshots
Source docs/assets/tapes/theme.tape
Output docs/assets/cli.gif
Set Width 1100
Set Height 760
Set FontSize 15
Set Framerate 10
Set TypingSpeed 45ms

Hide
Type "R=$PWD && source docs/assets/tapes/demo-shell.sh && bash $R/docs/assets/tapes/demo-zsh-setup.sh ~ && cd ~/web && exec zsh -i"
Enter
Sleep 3s
Ctrl+L
Sleep 500ms
Show

# zoxide: jump by a fragment of the name (the grey text is an autosuggestion).
Type "z ap"
Sleep 600ms
Enter
Sleep 800ms

# eza: a tree with icons and git status
Type "lt"
Sleep 300ms
Enter
Sleep 1800ms

# bat behind cat: syntax highlighting and the git change gutter
Type "cat src/routes.py"
Sleep 300ms
Enter
Sleep 2200ms
Ctrl+L

# fzf (Ctrl-T): fuzzy-find a file, with a preview
Ctrl+T
Sleep 800ms
Type "cach"
Sleep 1800ms
Escape
Sleep 300ms

# atuin (Ctrl-R): search everything you ran
Ctrl+R
Sleep 800ms
Type "test"
Sleep 1800ms
Escape
Sleep 400ms
Ctrl+L

# tokei: what the repo is made of
Type "tokei"
Sleep 300ms
Enter
Sleep 2500ms
Sleep 300ms
