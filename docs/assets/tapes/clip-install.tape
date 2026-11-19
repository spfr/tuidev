# docs/assets/clips/install.mp4 (and .gif, captioned by screenshots.sh): the
# one-line install as the README gives it, `curl -fsSL .../get.sh | bash`, in
# the demo home (/Users/Shared/NAME, as in sbx.tape). get.sh downloads the
# release, checks and unpacks it, asks what this machine should get (1,
# everything for agent work), then asks once more before it changes anything.
# `p` previews every change (the installer's --dry-run), and the clip ends on
# that question, asked again after the preview. Nothing is installed: the
# answer after the last frame, typed hidden, is n.
#
# What stands in for the network: `curl` is docs/assets/tapes/offline/curl,
# first on PATH. For the one-liner's URL and get.sh's two downloads
# (releases/latest/download/get.sh, tuidev.tar.gz and tuidev.tar.gz.sha256) it
# serves a release that scripts/dist.sh builds from this checkout's last
# commit, into the demo home, and it refuses any other URL. So a render needs
# no network and shows this checkout's get.sh and installer, not whichever
# release is the latest. The rest is real: get.sh's checksum and layout
# checks, the unpack to ~/.local/share/tuidev/versions/X.Y.Z, both questions
# and the dry run. The dry run is recorded hidden and shown once it has ended:
# its middle names the renderer's own SwiftBar plugin folder (read with
# `defaults`), which no shot may show. Render: make screenshots TAPES=clip-install
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
# The network's stand-in first on PATH, and the release it serves, built from
# this checkout.
Type `export DEMO_RELEASE="$HOME/.demo-release" PATH="$R/docs/assets/tapes/offline:$PATH"`
Enter
Type `TUIDEV_DIST_DIR="$DEMO_RELEASE" "$R/scripts/dist.sh" && cd && clear`
Enter
Sleep 4s
Show

# The one-liner, word for word as the README gives it.
Type "curl -fsSL https://github.com/spfr/tuidev/releases/latest/download/get.sh | bash"
Sleep 400ms
Enter
Sleep 4s

# What this machine should get: everything for agent work.
Type "1"
Sleep 300ms
Enter
Sleep 2500ms

# Preview first: the installer's dry run, shown once it has ended.
Type "p"
Sleep 300ms
Hide
Enter
Sleep 1500ms
Wait+Line@60s /\[n\]o:/
Show
Sleep 5s

Sleep 2s
# After the last frame: decline, so nothing is left waiting.
Hide
Type "n"
Enter
Sleep 1s
