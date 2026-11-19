# docs/assets/clips/install.mp4 (and .gif, captioned by screenshots.sh): the
# installer's dry run, what it would write and how it ends, then `tuidev check`
# with its Runtime section. Both are the real scripts, run from a copy of this
# checkout in the demo home (/Users/Shared/NAME, as in sbx.tape), so the paths
# on screen are the demo's. A dry run installs nothing, so the check that
# follows reports what is still missing and skips the runtime probes (no
# install is recorded there). Render: make screenshots TAPES=clip-install
Source docs/assets/tapes/theme.tape
Output docs/assets/clips/install.mp4
Set Width 1200
Set Height 720
Set FontSize 15
Set Framerate 10
Set TypingSpeed 30ms

Hide
# (On their own lines: a ~ is expanded when its line is read, before
# demo-env.sh has set HOME.)
Type `R="$PWD" && source docs/assets/tapes/demo-env.sh`
Enter
Type `mkdir "$HOME/tuidev" && tar -C "$R" --exclude .git --exclude docs/assets -cf - . | tar -C "$HOME/tuidev" -xf - && cd "$HOME/tuidev" && PATH="$HOME/tuidev/bin:$PATH"`
Enter
Sleep 3s
Type "clear"
Enter
Sleep 500ms
Show

# Everything it would change, shown before anything is.
Type "./install.sh --profile desktop --pack ai-clis --dry-run"
Sleep 300ms
Enter
Sleep 6s
Ctrl+L

# What is installed and what runs.
Type "tuidev check"
Sleep 300ms
Enter
Sleep 5s

Sleep 2s
