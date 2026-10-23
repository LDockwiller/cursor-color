#!/bin/bash
# Opt-in: adds (or updates) a "Style > Couleur du curseur" entry in the
# Omarchy menu by splicing extensions/omarchy-menu.snippet.jsonc into the
# user's own ~/.config/omarchy/extensions/omarchy-menu.jsonc. Run this
# yourself; nothing in this plugin edits your menu on its own.
set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SNIPPET="$PLUGIN_DIR/extensions/omarchy-menu.snippet.jsonc"
TARGET="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MARKER='"style.cursorcolor'

[[ -f $SNIPPET ]] || { echo "Missing $SNIPPET" >&2; exit 1; }

mkdir -p "$(dirname "$TARGET")"
[[ -f $TARGET ]] || printf '{\n}\n' > "$TARGET"

tmp=$(mktemp)
trap 'rm -f "$tmp" "$tmp.stripped"' EXIT

# Drop a previous copy of the entry (and its comment header), then insert the
# snippet just before the closing brace.
grep -vF -e "$MARKER" -e "io.github.ldockwiller.cursor-color." -e "tools/install-menu-entry.sh." "$TARGET" > "$tmp.stripped"
awk -v snippet="$SNIPPET" '
  /^}[[:space:]]*$/ && !done {
    while ((getline line < snippet) > 0) print line
    done = 1
  }
  { print }
' "$tmp.stripped" > "$tmp"

mv "$tmp" "$TARGET"
trap - EXIT
chmod +x "$PLUGIN_DIR/cursor-color"

echo "Entrée Style > Couleur du curseur ajoutée dans $TARGET"
