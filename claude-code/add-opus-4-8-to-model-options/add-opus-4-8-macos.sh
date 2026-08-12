#!/usr/bin/env bash
# Adds an "Opus 4.8" entry to the Claude Code model picker (terminal CLI and
# the VS Code extension) by setting the ANTHROPIC_CUSTOM_MODEL_OPTION env vars
# in the user-level settings file (~/.claude/settings.json).
#
# Safe to re-run: if the option is already configured, the script exits
# without touching anything. Otherwise a timestamped backup is created first.
#
# Needs python3 or node on PATH for the JSON merge.

set -euo pipefail

MODEL_ID="claude-opus-4-8"
MODEL_NAME="Opus 4.8"

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CONFIG_DIR/settings.json"

mkdir -p "$CONFIG_DIR"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"

merge_python() {
python3 - "$SETTINGS" "$MODEL_ID" "$MODEL_NAME" <<'PYEOF'
import json, sys

path, model_id, model_name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

env = data.get("env")
if not isinstance(env, dict):
    env = {}

# Already applied, nothing to do
if env.get("ANTHROPIC_CUSTOM_MODEL_OPTION") == model_id:
    sys.exit(10)

env["ANTHROPIC_CUSTOM_MODEL_OPTION"] = model_id
env["ANTHROPIC_CUSTOM_MODEL_OPTION_NAME"] = model_name
env["ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION"] = f"{model_name} · Previous Opus version"
data["env"] = env

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
}

merge_node() {
node -e '
const fs = require("fs");
const [path, modelId, modelName] = process.argv.slice(1);
const data = JSON.parse(fs.readFileSync(path, "utf8"));
const env = (data.env && typeof data.env === "object" && !Array.isArray(data.env)) ? data.env : {};
if (env.ANTHROPIC_CUSTOM_MODEL_OPTION === modelId) process.exit(10);
env.ANTHROPIC_CUSTOM_MODEL_OPTION = modelId;
env.ANTHROPIC_CUSTOM_MODEL_OPTION_NAME = modelName;
env.ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = modelName + " · Previous Opus version";
data.env = env;
fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n");
' "$SETTINGS" "$MODEL_ID" "$MODEL_NAME"
}

# The backup is removed again if the option turns out to be already applied,
# so a no-op run leaves no trace.
BACKUP="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)-$$"
cp "$SETTINGS" "$BACKUP"

status=0
if command -v python3 >/dev/null 2>&1; then
    merge_python || status=$?
elif command -v node >/dev/null 2>&1; then
    merge_node || status=$?
else
    rm -f "$BACKUP"
    echo "Error: need python3 or node on PATH to edit $SETTINGS" >&2
    exit 1
fi

if [ "$status" -eq 10 ]; then
    rm -f "$BACKUP"
    echo "Already applied: $MODEL_ID is set in $SETTINGS, nothing to do."
    exit 0
elif [ "$status" -ne 0 ]; then
    cp "$BACKUP" "$SETTINGS"
    echo "Error: failed to update $SETTINGS (restored from backup)." >&2
    exit "$status"
fi

echo "Added \"$MODEL_NAME\" ($MODEL_ID) to the Claude Code model picker."
echo "Settings: $SETTINGS"
echo "Backup:   $BACKUP"
echo "Start a new session (or reload the VS Code window) and check /model."
