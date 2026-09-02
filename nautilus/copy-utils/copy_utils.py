"""Copy Path / Name / URI / Contents / SHA-256 in the Nautilus context menu.

Drop-in nautilus-python extension, same mechanism as localsend.py and
transcode.py in ~/.local/share/nautilus-python/extensions/. Clipboard goes
through wl-copy, which outlives the Nautilus process on Wayland.

Multi-select joins values one per line. Right-clicking a folder's empty
background gets "Copy Folder Path" for the folder being viewed.
"""

import hashlib
import os
import shutil
import threading
from urllib.parse import unquote, urlparse

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import Gio, GLib, GObject, Nautilus

CONTENT_MAX_BYTES = 5 * 1024 * 1024
TEXT_MIME_EXTRAS = {
    "application/json",
    "application/xml",
    "application/x-yaml",
    "application/yaml",
    "application/toml",
    "application/x-shellscript",
    "application/javascript",
    "application/x-desktop",
    "application/x-perl",
    "application/x-php",
    "inode/x-empty",
}


def _copy_to_clipboard(text):
    wl_copy = shutil.which("wl-copy")
    if not wl_copy:
        return False
    process = Gio.Subprocess.new([wl_copy], Gio.SubprocessFlags.STDIN_PIPE)
    process.communicate(GLib.Bytes.new(text.encode("utf-8")), None)
    return True


def _notify(summary, body=""):
    notify_send = shutil.which("notify-send")
    if notify_send:
        Gio.Subprocess.new(
            [notify_send, "--app-name=Files", "--expire-time=2500", summary, body],
            Gio.SubprocessFlags.NONE,
        )


class CopyUtilsExtension(GObject.GObject, Nautilus.MenuProvider):
    # ----------------------------------------------------------- selections

    def _paths(self, files):
        paths = []
        for file in files:
            location = file.get_location()
            path = location.get_path() if location else None
            if path and path not in paths:
                paths.append(path)
        return paths

    def _uris(self, files):
        uris = []
        for file in files:
            uri = file.get_uri()
            if uri and uri not in uris:
                uris.append(uri)
        return uris

    def _text_like(self, file):
        mime = file.get_mime_type() or ""
        return mime.startswith("text/") or mime in TEXT_MIME_EXTRAS

    # ------------------------------------------------------------- actions

    def _on_copy_paths(self, _item, paths):
        _copy_to_clipboard("\n".join(paths))

    def _on_copy_names(self, _item, paths):
        _copy_to_clipboard("\n".join(os.path.basename(p.rstrip("/")) for p in paths))

    def _on_copy_uris(self, _item, uris):
        _copy_to_clipboard("\n".join(uris))

    def _on_copy_contents(self, _item, paths):
        total = 0
        chunks = []
        for path in paths:
            try:
                with open(path, "rb") as handle:
                    data = handle.read(CONTENT_MAX_BYTES + 1 - total)
            except OSError:
                continue
            total += len(data)
            if total > CONTENT_MAX_BYTES:
                _notify("Copy Contents", "Selection exceeds the 5 MB clipboard cap.")
                return
            try:
                chunks.append(data.decode("utf-8"))
            except UnicodeDecodeError:
                _notify("Copy Contents", f"{os.path.basename(path)} is not UTF-8 text.")
                return
        if not chunks:
            return
        _copy_to_clipboard("\n".join(chunks))
        _notify("Copy Contents", f"Copied {total:,} bytes from {len(chunks)} file(s).")

    def _on_copy_sha256(self, _item, paths):
        # Hashing can take a moment on big files; keep the UI thread free.
        def work():
            lines = []
            for path in paths:
                digest = hashlib.sha256()
                try:
                    with open(path, "rb") as handle:
                        for block in iter(lambda: handle.read(1 << 20), b""):
                            digest.update(block)
                except OSError:
                    continue
                lines.append(f"{digest.hexdigest()}  {os.path.basename(path)}")
            if not lines:
                return
            # Single file: just the hex digest, ready to paste into a compare.
            text = lines[0].split()[0] if len(lines) == 1 else "\n".join(lines)
            _copy_to_clipboard(text)
            _notify("SHA-256 copied", lines[0] if len(lines) == 1 else f"{len(lines)} files hashed.")

        threading.Thread(target=work, daemon=True).start()

    # ---------------------------------------------------------------- menu

    def _item(self, name, label, callback, payload):
        item = Nautilus.MenuItem(name=f"CopyUtils::{name}", label=label)
        item.connect("activate", callback, payload)
        return item

    def get_file_items(self, *args):
        files = args[0] if len(args) == 1 else args[1]
        paths = self._paths(files)
        if not paths:
            return []

        many = len(paths) > 1
        items = [
            self._item("path", "Copy Path" + ("s" if many else ""), self._on_copy_paths, paths),
            self._item("name", "Copy Name" + ("s" if many else ""), self._on_copy_names, paths),
            self._item("uri", "Copy URI" + ("s" if many else ""), self._on_copy_uris, self._uris(files)),
        ]

        regular = [f for f in files if f.get_location() and not f.is_directory()]
        if regular and len(regular) == len(files):
            if all(self._text_like(f) for f in files):
                items.append(self._item("contents", "Copy Contents", self._on_copy_contents, paths))
            items.append(self._item("sha256", "Copy SHA-256", self._on_copy_sha256, paths))

        return items

    def get_background_items(self, *args):
        current = args[0] if len(args) == 1 else args[1]
        if current is None:
            return []
        location = current.get_location()
        path = location.get_path() if location else None
        if not path:
            return []
        return [self._item("folder_path", "Copy Folder Path", self._on_copy_paths, [path])]
