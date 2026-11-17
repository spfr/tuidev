# docs/assets/remote.mp4 (remote.gif is cut from it, with the browser shot:
# docs/assets/tapes/README.md): "remote feels local". Herdr over this
# Mac and two Linux containers saved as atlas and kepler (remote-demo.sh), then
# `agents map` (prefix+m): the storefront preview on atlas opened through an
# ssh tunnel, a server left behind on kepler stopped from the same list, and
# the review a session on atlas wrote fetched and read here.
# The prompt shows no path: nothing of the machine that renders this is on
# screen. Start the fleet first, with TUIDEV_DEMO_NO_BROWSER=1 so no tab opens here:
#   TUIDEV_DEMO_NO_BROWSER=1 bash docs/assets/tapes/remote-demo.sh up /tmp/hd/aurora
#   DEMO_HOME=/tmp/hd/aurora vhs docs/assets/tapes/remote.tape
Source docs/assets/tapes/theme.tape
Output docs/assets/remote.mp4
Set Width 1500
Set Height 900
Set FontSize 15
Set Framerate 12

Hide
Type `eval "$(bash docs/assets/tapes/remote-demo.sh env "$DEMO_HOME")" && builtin cd "$HOME" && PS1='\[\e[1;32m\]❯\[\e[0m\] ' && clear`
Enter
Sleep 1s
Show

# Three machines in one sidebar: this Mac, atlas and kepler.
Type "herdr"
Sleep 300ms
Enter
Sleep 4s

# The storefront session on atlas started a preview: localhost, but atlas's.
Ctrl+B
Type "w"
Sleep 600ms
Down
Sleep 400ms
Down
Sleep 700ms
Enter
Sleep 4s

# Back to this Mac, and the map: what runs where, on every machine.
Ctrl+B
Type "w"
Sleep 500ms
Up
Sleep 300ms
Up
Sleep 500ms
Enter
Sleep 1500ms
Ctrl+B
Type "m"
Sleep 5s

# The preview on atlas: enter forwards it here and opens it.
Down
Sleep 500ms
Down
Sleep 1200ms
Enter
Sleep 5s

# The API server its session left behind on kepler: stop it (ctrl-k; ctrl-x
# is the same, and the one the browser VHS draws in passes on), y, gone.
Down
Sleep 1500ms
Ctrl+X
Sleep 3s
Type "y"
Enter
Sleep 2500ms
Enter
Sleep 4s

# The review the storefront session wrote, on atlas: enter fetches it here.
Down
Sleep 500ms
Down
Sleep 1500ms
Enter
Sleep 4s
Escape
Sleep 1s

# Detach, and read it: the file is on this Mac now.
Ctrl+B
Type "q"
Sleep 1500ms
Type "clear && glow ~/.local/state/tuidev/agents/remote/atlas/review.md"
Sleep 300ms
Enter
Sleep 6s
