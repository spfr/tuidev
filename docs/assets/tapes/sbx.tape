# docs/assets/sbx.png: sbx (strict) in the demo home. Render: make screenshots (macOS)
Source docs/assets/tapes/theme.tape
Set Width 920
Set Height 520

Hide
Type "source docs/assets/tapes/demo-env.sh && clear"
Enter
Sleep 1s
Show

Type "sbx -- cat README.md                    # project files: readable"
Enter
Sleep 600ms
Type "sbx -- cat ../.ssh/id_ed25519           # credentials: denied"
Enter
Sleep 600ms
Type "sbx -- touch ../.claude/settings.json   # agent settings: read-only"
Enter
Sleep 600ms
Type "sbx -- touch build.log && echo ok       # project files: writable"
Enter
Sleep 1500ms
Screenshot docs/assets/sbx.png
