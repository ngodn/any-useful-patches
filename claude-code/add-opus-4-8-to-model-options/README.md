# Add Opus 4.8 to the Claude Code model picker

Adds an "Opus 4.8" (`claude-opus-4-8`) entry to the model picker (`/model`) in
Claude Code, both the terminal CLI and the VS Code extension.

## How it works

Claude Code's picker code has a built-in hook (found in the bundled binary of
extension v2.1.228): if the `ANTHROPIC_CUSTOM_MODEL_OPTION` environment
variable is set, an extra entry is appended to the picker. The scripts set
that variable, plus its `_NAME` and `_DESCRIPTION` companions, in the `env`
block of the user-level settings file, so no binary patching is needed and
the change survives Claude Code and extension updates.

Settings file location (per the [official settings docs](https://code.claude.com/docs/en/settings)):

- Linux / macOS: `~/.claude/settings.json`
- Windows: `%USERPROFILE%\.claude\settings.json`
- If `CLAUDE_CONFIG_DIR` is set, the scripts use that directory instead.

The result in `settings.json`:

```json
"env": {
  "ANTHROPIC_CUSTOM_MODEL_OPTION": "claude-opus-4-8",
  "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME": "Opus 4.8",
  "ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION": "Opus 4.8 · Previous Opus version"
}
```

## Usage

Linux:

```bash
./add-opus-4-8-linux.sh
```

macOS (same script content, kept per-OS for clarity):

```bash
./add-opus-4-8-macos.sh
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\add-opus-4-8-windows.ps1
```

Then start a new Claude session (in VS Code: reload the window or open a new
conversation) and open the model picker.

## Behavior

- Idempotent: if `env.ANTHROPIC_CUSTOM_MODEL_OPTION` is already
  `claude-opus-4-8`, the script prints "Already applied" and exits without
  modifying or backing up anything.
- Otherwise it makes a timestamped backup (`settings.json.bak-...`) before
  writing, merges into the existing `env` block without dropping other keys,
  and restores the backup if the write fails.
- Creates `settings.json` (and the `.claude` dir) if they don't exist yet.
- Linux/macOS scripts need `python3` or `node` on PATH for the JSON merge.
  The Windows script only needs PowerShell (5.1 or 7+).

## Undo

Delete the three `ANTHROPIC_CUSTOM_MODEL_OPTION*` keys from the `env` block
in `settings.json`, or restore the `.bak-` file the script created.

## Caveats

- Only one custom slot exists; the hook supports a single extra model entry.
- The env var is undocumented, so a future Claude Code version could rename
  or remove it (verified working on v2.1.228, August 2026).
- The entry appears in the picker regardless of whether your account can use
  the model; selecting it only works if your plan has access to
  `claude-opus-4-8`.
- The Windows script round-trips the JSON through PowerShell, which may
  reformat whitespace in `settings.json`.
