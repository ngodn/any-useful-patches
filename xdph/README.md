# xdph screen sharing fix (Chrome on Hyprland, NVIDIA)

Status: FIXED and verified 2026-08-18 (Chrome screen share works again). Patched package `xdg-desktop-portal-hyprland 1.4.1-2`
built from `xdph/xdg-desktop-portal-hyprland/` (PKGBUILD + the two upstream patches)
and installed. Both patches applied cleanly on 1.4.1 (offset -12 lines, harmless).
Remaining: drop the local build once Arch ships > 1.4.1 (step 4, happens on its own
via `pacman -Syu`). To rebuild: `cd xdph/xdg-desktop-portal-hyprland && makepkg -sf` then
`pkexec pacman -U $PWD/xdg-desktop-portal-hyprland-1.4.1-2-x86_64.pkg.tar.zst`.
Note: `pkgctl` (devtools) is not installed; the package repo was cloned from
https://gitlab.archlinux.org/archlinux/packaging/packages/xdg-desktop-portal-hyprland.git

## Symptom

Screen sharing in Google Chrome stopped working. The Hyprland share picker opens,
you pick a screen, Chrome shows nothing / the share ends immediately.

## System snapshot (2026-08-18)

| Component | Version | Notes |
|---|---|---|
| xdg-desktop-portal-hyprland (xdph) | 1.4.1-1 (extra) | upgraded 2026-08-16 from 1.4.0 (1.4.0 came 2026-07-25 from 1.3.12) |
| Hyprland | 0.56.2-1 | upgraded 2026-08-16 |
| xdg-desktop-portal | 1.22.1-2 | |
| xdg-desktop-portal-gtk | 1.15.3-1 | |
| pipewire / wireplumber | 1.6.8 / 0.5.15 | |
| google-chrome | 151.0.7922.137 | upgraded 2026-08-17 |
| GPU | RTX 3060, nvidia-open-dkms 610.57.04 | DMA-BUF path in use |
| Monitors | HDMI-A-1 1080p60, DP-1 1440p@180, DP-2 4K@144 scale 1.5, DP-3 1080p60, myremote (headless) | shared output was DP-1 |

Config that is in place and fine:

- `/usr/share/xdg-desktop-portal/hyprland-portals.conf` -> `default=hyprland;gtk`
- `~/.config/hypr/xdph.conf`:
  ```
  screencopy {
      allow_token_by_default = true
      custom_picker_binary = hyprland-preview-share-picker
  }
  ```
- systemd user env has `WAYLAND_DISPLAY=wayland-1`, `XDG_CURRENT_DESKTOP=Hyprland`,
  `HYPRLAND_INSTANCE_SIGNATURE` set (uwsm).
- All user services running: pipewire, wireplumber, xdg-desktop-portal,
  xdg-desktop-portal-hyprland, xdg-desktop-portal-gtk.
  Only failed unit is `xdg-document-portal.service` (flatpak, unrelated).
- No `~/.config/chrome-flags.conf`, no special Chrome flags.

## Evidence

`journalctl --user -u xdg-desktop-portal-hyprland` at the moment Share was clicked
(2026-08-18 14:08:46):

```
[screencopy] restore data valid, not prompting
[screencopy] Start:
[screencopy]  | appid: com.google.Chrome
[pw] Building modifiers for dma
[screencopy] Sharing initialized
[screencopy] Sent restore token to ...
[pw] Building modifiers for dma
[screencopy/pipewire] Out of buffers
[sc] Retrying screencopy (1/10)
[pw] Building modifiers for dma
[pw] Building modifiers for dma
[ERR] [screencopy] tried scheduling on already scheduled cb (type 0)
[screencopy] Stream destroyed
[screencopy] Session destroyed
```

Chrome then retries a couple of times inside the same second (new session,
prompt, token, start, destroyed) and gives up.

## Root cause

Upstream regression in xdph 1.4.0 / 1.4.1, in `src/portals/Screencopy.cpp`.

When PipeWire briefly runs out of buffers on the first frames (normal backpressure,
pool of 4 buffers `XDPH_PWR_BUFFERS`), xdph renegotiates the stream via
`pw_stream_update_params()`. That call re-enters `PW_STREAM_STATE_STREAMING`
synchronously, which installs a fresh frame callback; the calling branch then
resets/destroys that new callback and queues a timer that later fails with
"tried scheduling on already scheduled cb". The session is left with no callback
and nothing queued, so the stream dies (or freezes later in long sessions).

Upstream references:

- Issue #423 "session freezes permanently after Out of buffers"
  https://github.com/hyprwm/xdg-desktop-portal-hyprland/issues/423
- PR #424 fix, merged 2026-08-06, commit `688feb3d`
  https://github.com/hyprwm/xdg-desktop-portal-hyprland/pull/424
- PR #425 "don't destroy the frame callback installed while renegotiating",
  merged 2026-08-17, commit `59d429bf` (covers the two remaining branches)
  https://github.com/hyprwm/xdg-desktop-portal-hyprland/pull/425
- Issue #418 same symptom ("starts for 1s and immediately stops")
  https://github.com/hyprwm/xdg-desktop-portal-hyprland/issues/418

Both fixes landed AFTER v1.4.1 (tagged 2026-07-29). No newer tag exists as of
2026-08-18, so the Arch package still carries the bug.

Commits on master past v1.4.1 (as of 2026-08-18):

```
8dca6c58 2026-08-01 ci: init vouch
b653ab53 2026-08-04 screencopy: don't send bad transform information over wire (#422)
688feb3d 2026-08-06 screencopy: fix permanent freeze after running out of buffers (#424)
9f0e9ff0 2026-08-11 nix: gcc 15 -> 16
59d429bf 2026-08-17 screencopy: don't destroy the frame callback installed while renegotiating (#425)
```

Not the cause: Chrome 151, PipeWire, portal config, env vars, NVIDIA driver
(they were checked and are fine). Reboot does not fix it, the bug is in the
installed binary; it is timing dependent so it may work once after a restart.

## Fix plan

### Step 0. Check whether Arch already shipped a fix

```
pacman -Sy && pacman -Si xdg-desktop-portal-hyprland | grep -E 'Version|Build Date'
```

If version is > 1.4.1 (or 1.4.1-2 with patches), just `pacman -Syu`, restart
services (step 3), and stop here. Also check
https://github.com/hyprwm/xdg-desktop-portal-hyprland/releases for v1.4.2.

### Step 1. Quick try (temporary at best)

```
systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal
```

Then test in Chrome (meet.google.com or https://mozilla.github.io/webrtc-landing/gum_test.html
"Screen" button). Might work due to timing luck, does not remove the bug.

### Step 2. Build patched xdph 1.4.1 (the real fix)

Keep it as a pacman package so the next official release replaces it cleanly.

```
cd ~/development/any-useful-patches/xdph
pkgctl repo clone --protocol=https xdg-desktop-portal-hyprland   # needs devtools
cd xdg-desktop-portal-hyprland

# fetch the two upstream fixes as patches
curl -fL -o 0001-fix-out-of-buffers-freeze.patch \
  https://github.com/hyprwm/xdg-desktop-portal-hyprland/commit/688feb3d.patch
curl -fL -o 0002-dont-destroy-frame-callback-while-renegotiating.patch \
  https://github.com/hyprwm/xdg-desktop-portal-hyprland/commit/59d429bf.patch
```

Edit PKGBUILD:

- bump `pkgrel` (e.g. `1` -> `1.1` or `2`)
- add both `.patch` files to `source=()` and `sha256sums=()` (`updpkgsums` fills them)
- add a `prepare()` (or extend it) that applies them:
  ```
  prepare() {
    cd "$pkgname-$pkgver"   # adjust to the source dir name in the PKGBUILD
    patch -Np1 -i "$srcdir/0001-fix-out-of-buffers-freeze.patch"
    patch -Np1 -i "$srcdir/0002-dont-destroy-frame-callback-while-renegotiating.patch"
  }
  ```

Then:

```
updpkgsums
makepkg -srci     # -s installs makedeps, -r removes them after, -c cleans, -i installs
```

Build deps already installed as of 2026-08-18: cmake 4.4, ninja, gcc 16,
hyprlang 0.6.8, hyprutils 0.14.1, hyprwayland-scanner 0.4.6, sdbus-cpp 2.3.1,
qt6-base 6.11. `hyprland-protocols` may need to be pulled by makepkg -s.

If a patch fails to apply cleanly on 1.4.1 (context drift from #422), fall back
to building master HEAD instead: set `source=("git+https://github.com/hyprwm/xdg-desktop-portal-hyprland.git#commit=59d429bf")`
with submodules as the -git PKGBUILD does (aur/xdg-desktop-portal-hyprland-git is
stale at 1.3.12, so adapt the extra PKGBUILD rather than using the AUR one).

Optional: add the package to `IgnorePkg` in `/etc/pacman.conf` ONLY if the repo
tries to "downgrade" back to 1.4.1-1; normally a higher pkgrel wins. Remove the
ignore once 1.4.2 is out.

### Step 3. Restart and verify

```
systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal
journalctl --user -fu xdg-desktop-portal-hyprland
```

Share the screen in Chrome. Success = after `Sharing initialized` you keep seeing
frame activity and no `tried scheduling on already scheduled cb` /
`Stream destroyed` right after start. Let it run a few minutes to make sure the
long-session freeze from #423 is gone too.

### Step 4. Cleanup later

When Arch ships xdph > 1.4.1 (with #424 and #425 included), `pacman -Syu` will
replace the local build. Remove any IgnorePkg entry if one was added.

## Notes / do not do

- Do not downgrade to 1.3.12 from the pacman cache: it links against older
  hyprutils / Hyprland ABIs (0.14.1 / 0.56.2 now) and will most likely crash.
- Not a Chrome flag problem; `WebRTC PipeWire Capturer` is on by default and the
  portal handshake completes fine.
- Root privileges on this machine: use `pkexec`, not `sudo`, for one-shot commands
  (makepkg -i will prompt via its own mechanism; if it needs sudo, run
  `pkexec pacman -U <built pkg>.pkg.tar.zst` instead).
