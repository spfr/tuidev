# docs/assets/clips/needs-you.mp4 (and .gif, captioned by screenshots.sh):
# `agents`, then `agents board` over the demo fixtures, as board.tape: the
# session blocked on a question comes first, with that question on the right.
# Render: make screenshots TAPES=clip-needs-you
Source docs/assets/tapes/theme.tape
Output docs/assets/clips/needs-you.mp4
Set Width 1200
Set Height 720
Set FontSize 15
Set Framerate 10
Set TypingSpeed 35ms

Hide
Type "export DEMO_PANES=1 && source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

# Three sessions; the api one waits on you.
Type "agents"
Sleep 300ms
Enter
Sleep 4s
Ctrl+L

# The board opens on it, with what it asks.
Type "agents board"
Sleep 300ms
Enter
Sleep 9s

Sleep 2s
