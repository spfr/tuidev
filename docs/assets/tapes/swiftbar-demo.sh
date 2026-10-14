#!/bin/bash
# Write a SwiftBar plugin that shows the agents menu over the demo fixtures,
# for capturing it by hand (SwiftBar can't be recorded headlessly):
#   swiftbar-demo.sh PLUGIN_DIR
# Point SwiftBar's plugin folder at PLUGIN_DIR, open the menu after its second
# refresh (Herdr status arrives on the first), and capture it. Steps:
# docs/assets/tapes/README.md. Menu actions do nothing: the demo `agents`
# never signals.
set -eo pipefail

dir="${1:?usage: swiftbar-demo.sh PLUGIN_DIR}"
tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$tapes/../../.." && pwd)"

mkdir -p "$dir"
dir="$(cd "$dir" && pwd -P)"
home="$dir/.demo-home/NAME"
bash "$tapes/demo-setup.sh" "$home"

plugin="$dir/agents-demo.10s.sh"
cat > "$plugin" <<EOF
#!/bin/bash
# The tuidev agents menu over the screenshot fixtures (docs/assets/tapes/README.md).
export DEMO_HOME=$(printf '%q' "$home") HOME=$(printf '%q' "$home")
export AGENTS_BIN=$(printf '%q' "$tapes/bin/agents")
exec /bin/bash $(printf '%q' "$repo/configs/swiftbar/agents.10s.sh") "\$@"
EOF
chmod +x "$plugin"
echo "wrote $plugin"
