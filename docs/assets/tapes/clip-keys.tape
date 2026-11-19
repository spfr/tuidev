# docs/assets/clips/keys.mp4 (and .gif, captioned by screenshots.sh): under
# sbx (strict), the demo's fake SSH key can't be read while `make test` runs,
# then `secret scan` names the made-up DEMO_TOKEN the demo ~/.zshrc exports,
# without printing it. The real sbx and secret, in the demo home
# (/Users/Shared/NAME, as in sbx.tape). Render: make screenshots TAPES=clip-keys
Source docs/assets/tapes/theme.tape
Output docs/assets/clips/keys.mp4
Set Width 1200
Set Height 640
Set FontSize 15
Set Framerate 10
Set TypingSpeed 30ms

Hide
Type "source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

Type "# an agent's commands, under sbx: your keys are out of reach"
Enter
Type "sbx -- cat ~/.ssh/id_ed25519"
Sleep 300ms
Enter
Sleep 1500ms
Type "# and the project's work still runs"
Enter
Type "sbx -- make test"
Sleep 300ms
Enter
Sleep 1500ms
Type "# a token left in your shell rc is named, never printed"
Enter
Type "secret scan"
Sleep 300ms
Enter
Sleep 3500ms

Sleep 2s
