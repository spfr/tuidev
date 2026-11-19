# docs/assets/clips/leftovers.mp4 (and .gif, captioned by screenshots.sh):
# what dead sessions left running (`agents stale`), why the dev server is
# "check first" (`agents why 4500`), and `agents reap -n`, which plans to stop
# only what is safe to and says what it left out. Over the demo fixtures, as
# cleanup.tape; the demo never signals anything. Render: make screenshots TAPES=clip-leftovers
Source docs/assets/tapes/theme.tape
Output docs/assets/clips/leftovers.mp4
Set Width 1200
Set Height 720
Set FontSize 15
Set Framerate 10
Set TypingSpeed 35ms

Hide
Type "source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

# Left behind by sessions that ended.
Type "agents stale"
Sleep 300ms
Enter
Sleep 3s
Ctrl+L

# Is the server safe to stop? Its verdict and the evidence.
Type "agents why 4500"
Sleep 300ms
Enter
Sleep 5s
Ctrl+L

# The cleanup takes only what is safe to stop.
Type "agents reap -n"
Sleep 300ms
Enter
Sleep 4s

Sleep 2s
