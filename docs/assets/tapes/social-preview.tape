# docs/assets/social-preview.png: the 1280x640 Open Graph card (upload it in
# the repo's Settings > Social preview). Text: social-card.sh. Render: make screenshots
Source docs/assets/tapes/theme.tape
Set Width 1280
Set Height 640
Set FontSize 26
Set Margin 36
Set Padding 30

Hide
Type "bash docs/assets/tapes/social-card.sh 20"
Enter
Sleep 1500ms
Show
Sleep 500ms
Screenshot docs/assets/social-preview.png
Sleep 500ms
