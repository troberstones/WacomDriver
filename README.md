# chWacomDriver

A pure-userspace macOS driver for the **Wacom Cintiq 21UX (DTK-2100)**, whose
official driver no longer works on modern macOS. No kext, no SIP changes.

The display is a plain DVI monitor and needs no driver — this project only
handles the USB pen digitizer: it seizes the tablet from macOS's mouse driver,
switches it into full "Wacom mode", and injects pressure/tilt tablet events.

See [PROTOCOL.md](PROTOCOL.md) for the reverse-engineered wire format.

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

## Run

```sh
.build/release/WacomTablet            # menu-bar app (icon in the status bar)
.build/release/WacomTablet --headless # no UI (for a LaunchAgent)
```

The menu-bar icon opens **Settings…** (button mapping, pressure curve,
calibration) and **Calibrate…**.

### Permissions (one-time)

`WacomTablet` needs, in System Settings ▸ Privacy & Security:

- **Input Monitoring** — to read the tablet
- **Accessibility** — to post pen events

Add the `WacomTablet` binary to both lists (a bare binary isn't auto-prompted as
reliably as a bundled `.app`). Relaunch after granting.

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

- `~/.config/wacomd/pad.json` — ExpressKeys / Touch Strips
- `~/.config/wacomd/pen.json` — calibration affine + pressure curve

Buttons are `L1`–`L8` (left, top→bottom), `R1`–`R8` (right), `LT`/`RT` (center
toggles). Defaults put ZBrush-style modifiers (Space/Shift/Ctrl/Alt) on `L5`–`L8`.
`WACOM_IDENTIFY=1 .build/release/WacomTablet --headless` prints each control's ID
as you press it.

## Status / roadmap

- [x] **M0** — reverse the protocol from live hardware (see PROTOCOL.md)
- [x] **M1** — pressure pen: position, pressure, tilt, proximity, tip + barrel buttons
- [x] **M3** — ExpressKeys + Touch Strips → configurable actions
- [x] **M2** — 4-point calibration + pressure curve, in a menu-bar settings UI
- [ ] **M4** — LaunchAgent packaging (.app bundle) + hot-plug handling
- [ ] eraser support (tool-type from the proximity packet)
- [ ] smooth hover position (jitter reduction while not drawing)
