# chWacomDriver

A pure-userspace macOS driver for the **Wacom Cintiq 21UX (DTK-2100)**, whose
official driver no longer works on modern macOS. No kext, no SIP changes.

The display is a plain DVI monitor and needs no driver — this project only
handles the USB pen digitizer: it seizes the tablet from macOS's mouse driver,
switches it into full "Wacom mode", and injects pressure/tilt tablet events.

See [PROTOCOL.md](PROTOCOL.md) for the reverse-engineered wire format.

## Install the prebuilt app (no build needed)

Each [release](https://github.com/troberstones/WacomDriver/releases) ships a
signed `WacomTablet.app.zip` for **Apple Silicon** Macs. To set it up:

```sh
# 1. Download WacomTablet.app.zip from the latest release, then:
cd ~/Downloads
unzip WacomTablet.app.zip

# 2. It's ad-hoc signed (not notarized), so clear the Gatekeeper quarantine:
xattr -dr com.apple.quarantine WacomTablet.app

# 3. Move it into place and launch it:
mv WacomTablet.app /Applications/
open /Applications/WacomTablet.app
```

A pencil icon appears in the menu bar. **Grant two permissions** in System
Settings ▸ Privacy & Security, then relaunch the app:

- **Input Monitoring** → enable `WacomTablet`
- **Accessibility** → enable `WacomTablet`

**Run at login:** either add `WacomTablet.app` in System Settings ▸ General ▸
Login Items, or — if you cloned the repo — run `./install.sh` to set up a
LaunchAgent that also auto-restarts it (see [Install (from source)](#install-from-source)).

Everything else (calibration, profiles, button mapping) is configured from the
app's menu-bar **Settings…**.

## Targets

| Target | Purpose |
|---|---|
| `WacomTablet` | The driver: menu-bar app (default) with a settings/calibration UI, or headless daemon via `--headless`. |
| `wacom-dump` | Diagnostic: hex-dump raw reports (used to reverse the protocol). |
| `wacom-inject-test` | Diagnostic: prove CGEvent pressure reaches apps. |

## Build

```sh
./build.sh          # builds to /tmp then copies into .build/release
```

`build.sh` exists because this repo's on-disk SwiftPM `build.db` hits intermittent
SQLite I/O errors on some filesystems; it builds via a `/tmp` scratch path to
avoid silently-skipped links. Plain `swift build -c release` works when the
filesystem cooperates.

## Install (from source)

Prefer the [prebuilt app](#install-the-prebuilt-app-no-build-needed) unless you
want run-at-login with auto-restart or you're hacking on the driver.

```sh
./install.sh
```

This builds the driver, assembles a proper `WacomTablet.app` (menu-bar only, no
Dock icon), installs it to `/Applications`, and loads a LaunchAgent so it **runs
at login and restarts on crash**. Unplug/replug is handled automatically.

Permissions attach to the signed bundle. By default it's **ad-hoc signed** —
stable until the next rebuild, after which you re-grant the two permissions. For
permissions that survive rebuilds, make a self-signed *Code Signing* certificate
in Keychain once and run `SIGN_IDENTITY="Your Cert Name" ./install.sh`.

Manage it:

```sh
tail -f ~/Library/Logs/com.chwacom.WacomTablet.log     # logs
launchctl bootout   gui/$(id -u)/com.chwacom.WacomTablet  # stop
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.chwacom.WacomTablet.plist  # start
./uninstall.sh                                         # remove (keeps config)
```

## Run from the build tree (dev)

```sh
.build/release/WacomTablet            # menu-bar app (icon in the status bar)
.build/release/WacomTablet --headless # no UI
```

The menu-bar icon opens **Settings…** (profiles, button mapping, pen buttons,
pressure curve, hover smoothing, calibration) and **Calibrate…**. Don't run this
manually while the LaunchAgent copy is loaded — both would fight over the tablet.

### Permissions (one-time)

`WacomTablet` needs, in System Settings ▸ Privacy & Security:

- **Input Monitoring** — to read the tablet
- **Accessibility** — to post pen events

With `./install.sh` you grant these to `WacomTablet.app`; the LaunchAgent keeps
it alive so it starts working right after you approve. Running the bare binary
from the build tree, add that binary to both lists instead.

### Runtime options (env vars)

| Var | Effect |
|---|---|
| `WACOM_INVERT_X=1` | Flip the pen horizontally if it's mirrored. |
| `WACOM_INVERT_Y=1` | Flip the pen vertically if it's upside-down. |
| `WACOM_DISPLAY=<n>` | Force target display by index (default: the 1600×1200 panel). |
| `WACOM_DEBUG=1` | Log every parsed pen/pad sample. |

## Verify it works

1. Run `WacomTablet`; it should seize the tablet and show a menu-bar icon.
2. Hover the pen — the cursor should track it on the Cintiq.
3. Open a pressure-aware app (Krita, Photoshop) and draw — stroke width/opacity
   should follow pen pressure.
4. Settings ▸ Calibration ▸ Run Calibration to align the tip with the cursor.

If the pen misbehaves as a plain mouse after quitting, unplug/replug the USB
cable to reset it out of Wacom mode.

## Config

Settings are edited in the app UI and stored as JSON:

- `~/.config/wacomd/profiles.json` — per-app profiles (button mapping, pen
  buttons, pressure curve); switch the active one from the menu bar
- `~/.config/wacomd/pen.json` — global calibration affine + hover smoothing

Buttons are `L1`–`L8` (left, top→bottom), `R1`–`R8` (right), `LT`/`RT` (center
toggles). Defaults put ZBrush-style modifiers (Space/Shift/Ctrl/Alt) on `L5`–`L8`.
`WACOM_IDENTIFY=1 .build/release/WacomTablet --headless` prints each control's ID
as you press it.

## Status / roadmap

- [x] **M0** — reverse the protocol from live hardware (see PROTOCOL.md)
- [x] **M1** — pressure pen: position, pressure, tilt, proximity, tip + barrel buttons
- [x] **M3** — ExpressKeys + Touch Strips → configurable actions
- [x] **M2** — 4-point calibration + pressure curve, in a menu-bar settings UI
- [x] profiles (per-app configs) + pen-button assignment
- [x] **M4** — `.app` bundle + LaunchAgent (`install.sh`) + hot-plug handling
- [x] eraser support (tool-type from the proximity packet)
- [x] hover smoothing (1€ filter; jitter reduction while not drawing)
