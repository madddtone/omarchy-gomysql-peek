#!/usr/bin/env bash
# Setup for the GoMySQL Peek omarchy shell plugin.
#
# This builds the Go engine to ~/.local/bin/omysql-engine — the one step
# `omarchy plugin add` can't do for you:
#   omarchy plugin add https://github.com/madddtone/omarchy-gomysql-peek.git --enable
#   ~/.config/omarchy/plugins/madddtone.gomysql-peek/install.sh
#
# It never touches the plugin files themselves; those stay managed by
# `omarchy plugin add/update`.
# From any other checkout it does the same build; sync the plugin files with
# `omarchy plugin update` instead (linking over the managed checkout breaks updates).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_BIN="$HOME/.local/bin/omysql-engine"
PLUGIN_ID="madddtone.gomysql-peek"

if ! command -v go >/dev/null 2>&1; then
  echo "error: go is required to build the engine (install go with your package manager)" >&2
  exit 1
fi

echo "==> Building engine -> $ENGINE_BIN"
(cd "$REPO_DIR/engine" && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$ENGINE_BIN" .)

echo
echo "Engine built. Then sync the plugin and restart the shell:"
echo "  omarchy plugin update $PLUGIN_ID --yes"
echo "  omarchy restart shell"
echo
echo "Summon it with:"
echo "  omarchy-shell shell toggle $PLUGIN_ID"
echo "or bind a key in ~/.config/hypr/bindings.lua, e.g.:"
echo "  o.bind(\"SUPER + M\", \"\", \"omarchy-shell shell toggle $PLUGIN_ID\")"
