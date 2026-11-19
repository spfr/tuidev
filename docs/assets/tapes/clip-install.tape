# docs/assets/clips/install.mp4 (and .gif, captioned by screenshots.sh): the
# installer's dry run for the full profile. First its opening screen (the
# profile, the packs, the first steps it would take), then the whole run, which
# ends with what to do next and the steps it would leave to you. The real
# install.sh, run from a copy of this checkout in the demo home
# (/Users/Shared/NAME, as in sbx.tape), so the paths on screen are the demo's.
# The whole run is recorded hidden and shown once it has ended: its middle
# names the renderer's own SwiftBar plugin folder (read with `defaults`), which
# no shot may show. Render: make screenshots TAPES=clip-install
Source docs/assets/tapes/theme.tape
Output docs/assets/clips/install.mp4
Set Width 1200
Set Height 720
Set FontSize 15
Set Framerate 10
Set TypingSpeed 30ms

Hide
# Nothing on PATH from the renderer's home: the herdr pack would name a herdr
# found there. (Each on its own line: a ~ or $HOME is expanded when its line is
# read, and demo-env.sh changes HOME.)
Type `PATH="$(printf '%s' "$PATH" | tr : '\n' | grep -v "^$HOME/" | paste -sd: -)"`
Enter
Type `R="$PWD" && source docs/assets/tapes/demo-env.sh`
Enter
Type `mkdir "$HOME/tuidev" && tar -C "$R" --exclude .git --exclude docs/assets -cf - . | tar -C "$HOME/tuidev" -xf - && cd "$HOME/tuidev"`
Enter
Sleep 3s
Type "clear"
Enter
Sleep 500ms
Show

# What it would do, before it does anything: its opening screen.
Type "./install.sh --profile full --dry-run 2>&1 | head -24"
Sleep 300ms
Enter
Sleep 6s
Ctrl+L

# The whole dry run, shown once it has ended.
Type "./install.sh --profile full --dry-run"
Sleep 400ms
Hide
Enter
Sleep 3s
Show
Sleep 5s

Sleep 2s
