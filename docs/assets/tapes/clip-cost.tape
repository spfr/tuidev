# docs/assets/clips/cost.mp4 (and .gif, captioned by screenshots.sh):
# `agents limits`, then `agents report` (CPU by job and project, tokens and
# their API-equivalent cost), over the demo's made-up week (demo-history.sh;
# priced models only, from lib/agents/prices.tsv).
# Render: make screenshots TAPES=clip-cost
Source docs/assets/tapes/theme.tape
Output docs/assets/clips/cost.mp4
Set Width 1200
Set Height 900
Set FontSize 15
Set Framerate 10
Set TypingSpeed 35ms

Hide
Type "source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

# How much of each plan's window is left.
Type "agents limits"
Sleep 300ms
Enter
Sleep 4s
Ctrl+L

# Where the day's CPU and tokens went, and what they would cost.
Type "agents report"
Sleep 300ms
Enter
Sleep 8s

Sleep 2s
