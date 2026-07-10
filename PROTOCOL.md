# Cintiq 21UX (DTK-2100) USB protocol — reverse-engineered

Decoded from a live capture of this machine's own DTK-2100 (VID `0x056a` /
PID `0x00cc`) via `Sources/wacom-dump`. 4,183 real reports analysed. This is the
Wacom "Intuos-family / Protocol 5" pen format plus a separate pad report.

## Enumeration & activation

- The device powers up in **HID mouse-emulation mode** (macOS binds it as a boot
  mouse → cursor moves, no pressure).
- Open the HID device with **`kIOHIDOptionsTypeSeizeDevice`** (works as a normal
  user on macOS 15.6 — no sudo, no kext).
- **Switch to Wacom mode** with a Feature `SetReport`:
  - Report ID **2**, payload **must be 2 bytes** (`{0x02, 0x02}` works; a 1-byte
    payload fails with `0xe0005000` = bad length).
- After the switch the device streams raw input reports on the interrupt-IN
  endpoint. Read them with `IOHIDDeviceRegisterInputReportCallback` (raw bytes —
  they no longer match the HID report descriptor).

Two report IDs are emitted: **`0x02` = pen**, **`0x0c` = pad** (ExpressKeys /
Touch Strips). Both are 10 bytes including the report-ID byte.

Below, `d[0]` is the report-ID byte (`0x02` or `0x0c`), `d[1]`..`d[9]` the payload.

## Pen report (ID `0x02`)

Packet type is decided by `d[1] & 0xb8`:

| `d[1] & 0xb8` | meaning |
|---|---|
| `0xa0` | **pen data** (position / pressure / tilt) — the common case |
| `0x80`, `d[1]==0xc2` | **tool entering** proximity (tool id / serial packet) |
| `0x80`, `d[1]==0x80`, rest 0 | **tool leaving** proximity |

### Pen data packet (`d[1] & 0xb8 == 0xa0`)

```
X        = (d[2] << 9) | (d[3] << 1) | ((d[9] >> 1) & 1)      // observed 18312..84619
Y        = (d[4] << 9) | (d[5] << 1) |  (d[9]       & 1)      // observed 12904..61867
pressure = (d[6] << 3) | ((d[7] & 0xC0) >> 5) | (d[1] & 0x01) // 11-bit, observed exactly 0..2047
tiltX    = (((d[7] << 1) & 0x7E) | (d[8] >> 7)) - 64          // 7-bit signed, centre 64
tiltY    =   (d[8] & 0x7F)                       - 64          // 7-bit signed, centre 64
barrelButton1 = d[1] & 0x02                                    // BTN_STYLUS
barrelButton2 = d[1] & 0x04                                    // BTN_STYLUS2
tipDown       = pressure > threshold  (~a small value, e.g. > 10)
```

Notes:
- `d[1]` low bits confirmed live: `0xe0` base; `+1` = pressure LSB, `+2` = barrel
  button 1 (124 hits), `+4` = barrel button 2 (36 hits). Values `e0`,`e1`,`e2`,
  `e3`,`e4`,`e5` all seen.
- Full logical range for the 21UX2 is ~`0..87200` (X) × `0..65600` (Y) at
  100 units/mm; the observed ranges are just where the pen was moved.
- `distance`/hover height is derivable from the proximity packets; hover events
  arrive as pen packets with `pressure == 0`.

### Tool proximity packets
- Enter: `02 c2 80 21 58 03 b9 21 00 00` — carries tool type/serial; treat as
  "pen entered, deviceID = …". Emit a CGEvent tablet **proximity-in**.
- Leave: `02 80 00 00 00 00 00 00 00 00` — emit **proximity-out**.

## Pad report (ID `0x0c`) — ExpressKeys & Touch Strips

Format `0c 00 d2 d3 d4 d5 d6 d7 d8 d9`. Confirmed live:

```
ExpressKeys = bitmask spread across d[3] and d[4]
  d[3] bits seen: 0x01 0x02 0x04 0x10   (one bezel column)
  d[4] bits seen: 0x01 0x04 0x08 0x20 0x40 0x80  (other bezel column)
Touch Strips:
  d[8] = one strip's absolute finger position (values 0x00..0x08+ seen while sliding)
  d[9] = the other strip's position
```

Exact per-key bit → physical-button mapping and the full strip value range should
be finalised by pressing each key/strip one at a time and logging (a labelled
capture pass). The structure above is confirmed; the exhaustive bit map is the
only remaining detail.

## Cross-check

Matches Linux `input-wacom` `wacom_wac.c` `wacom_intuos_irq()` for the
Intuos/Cintiq2 family, which is the authoritative reference if any edge case
(e.g. mouse/lens-cursor tool, or the tool-id decode in the proximity packet) is
needed.
