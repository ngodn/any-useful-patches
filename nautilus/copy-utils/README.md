# Nautilus copy-utils: Copy Path & friends in the right-click menu

Status: DONE 2026-09-02. Installed and verified on nautilus 50.2.2 with
nautilus-python 4.1.0 (both already present; "Send via LocalSend" and
"Transcode" use the same mechanism).

## What it adds

Right-click on files/folders in GNOME Files:

- **Copy Path(s)** — absolute path, multi-select joins one per line
- **Copy Name(s)** — bare filename(s)
- **Copy URI(s)** — file:// URIs
- **Copy Contents** — file text onto the clipboard (UTF-8 text files only,
  5 MB cap, notification on result); shown only when every selected item
  is a text-like file
- **Copy SHA-256** — single file: bare hex digest; multi: `sha256sum`-style
  lines; hashed off the UI thread, result via notification

Right-click on a folder's empty background: **Copy Folder Path**.

Clipboard goes through `wl-copy` (wl-clipboard), which owns the selection
independently of the Nautilus process, so the clipboard survives closing
the window.

## Install / update

```
./install.sh
```

Copies `copy_utils.py` to `~/.local/share/nautilus-python/extensions/` and
quits Nautilus (`nautilus -q`); the next window loads it. Pure user-level
files, nothing owned by pacman, so nothing to re-apply after upgrades.

To remove: delete the file from the extensions dir and `nautilus -q`.

## Notes

- nautilus-python extensions run inside the Nautilus process; errors show
  up on the terminal Nautilus was started from (or the journal).
- Alternative considered: chr314/nautilus-copy-path (AUR), configurable
  with keyboard shortcuts. This local version was preferred to keep the
  exact feature set versioned in this repo, consistent with localsend.py.
