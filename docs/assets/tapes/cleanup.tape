# docs/assets/cleanup.gif: `agents` finds a polling loop stuck for 5h, `agents why`
# shows it is safe to stop, and `agents report` shows where the CPU went, over
# the demo fixtures and their made-up history. Render: make screenshots
Source docs/assets/tapes/theme.tape
Output docs/assets/cleanup.gif
Set Width 1250
Set Height 800
Set FontSize 15
Set Framerate 10
Set TypingSpeed 30ms

Hide
Type "source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

# What runs: the api session has waited on a polling loop for 5h.
Type "agents"
Enter
Sleep 4s
Ctrl+L

# Is it safe to stop? The evidence and a verdict.
Type "agents why 2120"
Enter
Sleep 5s
Ctrl+L

# Where the CPU went today, and what was cleaned up.
Type "agents report"
Enter
Sleep 5s
