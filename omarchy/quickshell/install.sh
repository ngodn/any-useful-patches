#!/bin/bash
# Install the Antigravity agent support into the local Omarchy 4 install.
#
# - the usage collector and panel icons are ADDITIVE files: pacman does not
#   own them, so omarchy package upgrades leave them alone.
# - omarchy-default-agent / omarchy-agent are pacman-owned and patched in
#   place: an omarchy upgrade reverts them, re-run this script afterwards.
#
# Root actions use pkexec (Polkit prompt).
set -euo pipefail
cd "$(dirname "$0")"

OMARCHY=/usr/share/omarchy
AGENTS_PLUGIN=$OMARCHY/shell/plugins/agents

echo "==> Installing collector + icons (additive)"
pkexec bash -c "
  set -e
  install -m755 '$PWD/bin/omarchy-agent-usage-antigravity' '$OMARCHY/bin/omarchy-agent-usage-antigravity'
  install -m644 '$PWD/assets/antigravity.svg' '$AGENTS_PLUGIN/assets/antigravity.svg'
  install -m644 '$PWD/assets/antigravity-light.svg' '$AGENTS_PLUGIN/assets/antigravity-light.svg'
  for p in '$PWD'/patches/*.patch; do
    # bin entries may be symlinks into /usr/bin; patch the real file.
    target=\$(readlink -f \"$OMARCHY/bin/\$(basename \"\$p\" -antigravity.patch)\")
    if patch -R -s -f --dry-run \"\$target\" <\"\$p\" >/dev/null 2>&1; then
      echo \"    \$target: already patched\"
    else
      patch --no-backup-if-mismatch \"\$target\" <\"\$p\"
    fi
  done
"

echo "==> Refreshing usage records"
OMARCHY_PATH=$OMARCHY "$OMARCHY/bin/omarchy-agent-usage-update" antigravity || true

echo "==> Done. Menu row: merge extensions/omarchy-menu-antigravity.jsonc into"
echo "    ~/.config/omarchy/extensions/omarchy-menu.jsonc (see README)."
