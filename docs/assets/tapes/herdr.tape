# docs/assets/herdr.gif and herdr.png: one Herdr sidebar over three machines,
# this Mac (Local) and two Linux containers saved as devbox and workbox, with
# agent stand-ins (herdr/demo-agent.sh) and tuidev on each: tabs named after
# what runs in them, and tuidev's sidebar rows (roll-ups, blocked counts, since
# when). scripts/screenshots.sh starts the fleet with herdr-demo.sh before this
# tape and removes it after. Render: make screenshots
Source docs/assets/tapes/theme.tape
Output docs/assets/herdr.gif
Set Width 1100
# Tall enough for every workspace and agent row in the sidebar.
Set Height 960
Set FontSize 15
Set Framerate 10

Hide
# (A prompt with no path in it: `cd ~` on the line that sets HOME still goes
# to the home of whoever renders this, and the prompt then names it.)
# `go`: two stand-ins finish a few seconds after it, with the client attached.
Type `bash docs/assets/tapes/herdr-demo.sh go "$DEMO_HOME" && eval "$(bash docs/assets/tapes/herdr-demo.sh env "$DEMO_HOME")" && builtin cd "$HOME" && PS1='\[\e[1;32m\]❯\[\e[0m\] ' && clear`
Enter
Sleep 2s
Show

# Every machine's agents in one sidebar; api on devbox is blocked. Two
# stand-ins finish while this client watches, so it shows them as done.
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

# Answer it; the agent carries on and its row turns from blocked to idle
# (done is for a completion you were not looking at).
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
