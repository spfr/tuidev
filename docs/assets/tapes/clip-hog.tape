# docs/assets/clips/hog.mp4 (and .gif, captioned by screenshots.sh): a test
# run grows past the memory guard's warning size. `agents hogs` lists it,
# `agents why` gives its verdict, `agents mem` shows it against the guard's
# warning and stop sizes, with the warning the guard recorded. DEMO_HOG=1
# adds the runaway (fixtures/hog/) and that incident to the demo fixtures.
# Render: make screenshots TAPES=clip-hog
Source docs/assets/tapes/theme.tape
Output docs/assets/clips/hog.mp4
Set Width 1200
Set Height 720
Set FontSize 15
Set Framerate 10
Set TypingSpeed 35ms

Hide
Type "export DEMO_HOG=1 && source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

# A test run is past 9 GB.
Type "agents hogs"
Sleep 300ms
Enter
Sleep 3s
Ctrl+L

# Its verdict.
Type "agents why 1311"
Sleep 300ms
Enter
Sleep 4s
Ctrl+L

# The guard warned at 8G and stops it at 24G, before macOS runs out.
Type "agents mem"
Sleep 300ms
Enter
Sleep 5s

Sleep 2s
