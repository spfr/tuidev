# docs/assets/herdr.gif and herdr.png: one Herdr sidebar over three machines,
# this Mac (Local) and two Linux containers saved as devbox and workbox, with
# agent stand-ins (herdr/demo-agent.sh). scripts/screenshots.sh starts the fleet
# with herdr-demo.sh before this tape and removes it after. Render: make screenshots
Source docs/assets/tapes/theme.tape
Output docs/assets/herdr.gif
Set Width 1100
Set Height 800
Set FontSize 15
Set Framerate 10

Hide
Type `eval "$(bash docs/assets/tapes/herdr-demo.sh env "$DEMO_HOME")" && cd ~ && PS1='\[\e[1;36m\]\w\[\e[0m\] \[\e[1;32m\]❯\[\e[0m\] ' && clear`
Enter
Sleep 1s
Show

# Every machine's agents in one sidebar; api on devbox is blocked.
Type "herdr"
Sleep 300ms
Enter
Sleep 4s

# Jump to it: prefix (Ctrl+b), w, then down to devbox · api.
Ctrl+B
Type "w"
Sleep 600ms
Down
Sleep 500ms
Down
Sleep 700ms
Enter
Sleep 2500ms
Screenshot docs/assets/herdr.png
Sleep 1s

# Answer it; the agent carries on and its dot turns from red to done.
Type "y"
Sleep 3500ms

# The next machine over: workbox · infra.
Ctrl+B
Type "w"
Sleep 500ms
Down
Sleep 400ms
Down
Sleep 600ms
Enter
Sleep 3500ms
