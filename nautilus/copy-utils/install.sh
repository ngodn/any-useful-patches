#!/bin/bash
# Install the copy-utils Nautilus extension for the current user (no root).
set -euo pipefail
cd "$(dirname "$0")"
dest="$HOME/.local/share/nautilus-python/extensions"
mkdir -p "$dest"
install -m644 copy_utils.py "$dest/copy_utils.py"
nautilus -q 2>/dev/null || true   # next window loads the extension
echo "Installed. Open a Files window and right-click."
