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
| `wacomd` | The driver daemon (Milestone 1: pressure pen). |
| `wacom-dump` | Diagnostic: hex-dump raw reports (used to reverse the protocol). |
| `wacom-inject-test` | Diagnostic: prove CGEvent pressure reaches apps. |

## Build

```sh
swift build -c release
```

## Run

```sh
.build/release/wacomd
```

### Permissions (one-time)

Grant the app you launch `wacomd` from (Terminal, iTerm, …):

- **Input Monitoring** — System Settings ▸ Privacy & Security ▸ Input Monitoring
  (lets it read the tablet)
- **Accessibility** — System Settings ▸ Privacy & Security ▸ Accessibility
  (lets it post pen events)

Then quit and relaunch that terminal so the grants take effect.

### Runtime options (env vars)

| Var | Effect |
|---|---|
| `WACOM_INVERT_X=1` | Flip the pen horizontally if it's mirrored. |
| `WACOM_INVERT_Y=1` | Flip the pen vertically if it's upside-down. |
| `WACOM_DISPLAY=<n>` | Force target display by index (default: the 1600×1200 panel). |
| `WACOM_DEBUG=1` | Log every parsed pen/pad sample. |

## Verify it works

1. Run `wacomd`; it should print "Tablet seized and switched to Wacom mode."
2. Hover the pen — the cursor should track it on the Cintiq.
3. Open a pressure-aware app (Krita, Photoshop) and draw — stroke width/opacity
   should follow pen pressure.
4. If the pen axis is mirrored/flipped, set `WACOM_INVERT_X` / `WACOM_INVERT_Y`.

If the pen misbehaves as a plain mouse after stopping the daemon, unplug/replug
the USB cable to reset it out of Wacom mode.

## Status / roadmap

- [x] **M0** — reverse the protocol from live hardware (done; see PROTOCOL.md)
- [x] **M1** — pressure pen: position, pressure, tilt, proximity, tip + barrel buttons
- [x] **M3** — ExpressKeys + Touch Strips → configurable actions (see below)
- [ ] **M2** — 4-point calibration + pressure curve
- [ ] **M4** — LaunchAgent packaging + hot-plug handling
- [ ] eraser support (tool-type from the proximity packet)

### ExpressKeys / Touch Strips

Buttons are `L1`–`L8` (left, top→bottom), `R1`–`R8` (right), `LT`/`RT` (center
toggles). Defaults put ZBrush-style modifiers (Space/Shift/Ctrl/Alt) on `L5`–`L8`.
Customize via `WACOM_DUMP_CONFIG=1 .build/release/wacomd > ~/.config/wacomd/pad.json`,
then edit. `WACOM_IDENTIFY=1` prints each control's ID as you press it.
