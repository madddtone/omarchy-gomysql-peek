#!/usr/bin/env bash
# Setup for the GoMySQL Peek omarchy shell plugin.
#
# Inside an installed plugin checkout (~/.config/omarchy/plugins/...) it only
# builds the engine — that's the one step `omarchy plugin add` can't do for you:
#   omarchy plugin add https://github.com/madddtone/omarchy-gomysql-peek.git --enable
#   ~/.config/omarchy/plugins/madddtone.gomysql-peek/install.sh
#
# From a plain checkout (development) it does the full local install:
# builds the engine, links the plugin files into ~/.config/omarchy/plugins,
# enables it, and restarts the shell.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_BIN="$HOME/.local/bin/omysql-engine"
PLUGIN_ID="madddtone.gomysql-peek"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

if ! command -v go >/dev/null 2>&1; then
  echo "error: go is required to build the engine (sudo pacman -S go)" >&2
  exit 1
fi

echo "==> Building engine -> $ENGINE_BIN"
(cd "$REPO_DIR/engine" && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$ENGINE_BIN" .)

if [[ "$REPO_DIR" == "$HOME/.config/omarchy/plugins/"* ]]; then
  echo
  echo "Done. Summon it with:"
  echo "  omarchy-shell shell toggle $PLUGIN_ID"
  exit 0
fi

echo "==> Linking plugin -> $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
for f in manifest.json DbPeek.qml Peek.js install.sh README.md LICENSE; do
  [[ -f "$REPO_DIR/$f" ]] || continue
  if [ -e "$PLUGIN_DIR/$f" ] && [ ! -L "$PLUGIN_DIR/$f" ]; then
    mv "$PLUGIN_DIR/$f" "$PLUGIN_DIR/$f.bak.$(date +%s)"
  fi
  ln -sfn "$REPO_DIR/$f" "$PLUGIN_DIR/$f"
done

echo "==> Enabling plugin"
omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 || true

echo "==> Restarting omarchy shell"
omarchy restart shell

echo
echo "Installed. Summon it with:"
echo "  omarchy-shell shell toggle $PLUGIN_ID"
echo "or bind a key in ~/.config/hypr/bindings.lua, e.g.:"
echo "  o.bind(\"SUPER + M\", \"\", \"omarchy-shell shell toggle $PLUGIN_ID\")"
