# docs/assets/board.gif and board.png: `agents board` over the demo fixtures.
# Three sessions (one needs you, one to review, one working): the right-hand
# side follows the cursor with that session's last lines of output, then the
# Tree lens lists what runs under each. Render: make screenshots TAPES=board
#
# This is the board in a plain terminal. In Herdr it opens with prefix+space
# as a popup over the pane you are in; VHS records one terminal, not Herdr's
# popup, so the frame around it is not shown here. The panes' text is made up
# (fixtures/panes/, read through the demo's `herdr pane read` stub).
Source docs/assets/tapes/theme.tape
Output docs/assets/board.gif
Set Width 1500
Set Height 800
Set FontSize 15
Set Framerate 10

Hide
Type "export DEMO_PANES=1 && source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

# It opens on the session that needs you: the question it asks is on the right.
Type "agents board"
Sleep 400ms
Enter
Sleep 4s
Screenshot docs/assets/board.png
Sleep 600ms

# Down to the one that finished: what it did, to review.
Down@120ms 3
Sleep 3500ms

# And the one still working.
Down@120ms 3
Sleep 3s

# tab: the Tree lens, each session with the commands under it.
Tab
Sleep 3500ms
