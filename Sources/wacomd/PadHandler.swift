// PadHandler.swift — turn pad reports into keystrokes / scrolls.
//
// ExpressKeys are 8-bit bitmasks (left = d6, right = d8); we diff against the
// previous state and fire on press (and release, for held modifiers). Toggles
// are single bits. Touch Strips report a one-hot position; sliding changes it
// and the direction drives the strip action.

import Foundation

final class PadHandler {
    private let config: PadConfig
    private let mods: SharedModifiers
    private let identify = ProcessInfo.processInfo.environment["WACOM_IDENTIFY"] == "1"

    private var prevLeft: UInt8 = 0
    private var prevRight: UInt8 = 0
    private var prevLT = false
    private var prevRT = false
    private var prevLeftStrip = -1
    private var prevRightStrip = -1

    init(config: PadConfig, mods: SharedModifiers) {
        self.config = config
        self.mods = mods
        if identify {
            print("\n=== IDENTIFY MODE ===  press each control; nothing is injected.")
            print("IDs: L1..L8 left keys (top→bottom), R1..R8 right keys, LT/RT toggles.\n")
        }
    }

    func handle(_ p: PadSample) {
        handleKeys(p.leftKeys, prev: &prevLeft, prefix: "L")
        handleKeys(p.rightKeys, prev: &prevRight, prefix: "R")
        handleToggle(p.leftToggle, prev: &prevLT, id: "LT")
        handleToggle(p.rightToggle, prev: &prevRT, id: "RT")
        handleStrip(p.leftStrip, prev: &prevLeftStrip, action: config.leftStrip, name: "left")
        handleStrip(p.rightStrip, prev: &prevRightStrip, action: config.rightStrip, name: "right")
    }

    // MARK: keys / toggles

    private func handleKeys(_ bits: UInt8, prev: inout UInt8, prefix: String) {
        let changed = bits ^ prev
        prev = bits
        guard changed != 0 else { return }
        for i in 0..<8 where changed & (UInt8(1) << i) != 0 {
            fire("\(prefix)\(i + 1)", pressed: bits & (UInt8(1) << i) != 0)
        }
    }

    private func handleToggle(_ on: Bool, prev: inout Bool, id: String) {
        guard on != prev else { return }
        prev = on
        fire(id, pressed: on)
    }

    private func fire(_ id: String, pressed: Bool) {
        if identify {
            print("\(id) \(pressed ? "DOWN" : "up")")
            return
        }
        guard let action = config.buttons[id] else {
            if pressed { print("unmapped button \(id) — add it to your config") }
            return
        }
        switch action.type {
        case "hold":
            // A modifier hold is tracked as flags (stamped onto every event, so
            // it also affects drawing). A non-modifier hold (e.g. Space) posts a
            // real key down/up.
            if let mask = KeyCodes.modifierMask(action.key) {
                if pressed { mods.flags.insert(mask) } else { mods.flags.remove(mask) }
                KeyCodes.postModifier(mask, down: pressed, base: mods.flags)
            } else {
                KeyCodes.postKey(action.key, down: pressed, base: mods.flags)
            }
        case "chord":
            if pressed { KeyCodes.postChord(mods: action.mods ?? [], key: action.key, base: mods.flags) }
        default: break
        }
    }

    // MARK: touch strips

    private func handleStrip(_ pos: Int, prev: inout Int, action: StripAction, name: String) {
        let z = pos
        defer { prev = z }
        guard z >= 0, prev >= 0, z != prev else { return } // continuous contact + movement
        // Position index decreases as the finger moves toward the top.
        let towardTop = z < prev

        if identify {
            print("\(name) strip \(prev) -> \(z) (\(towardTop ? "up" : "down"))")
            return
        }
        switch action.mode {
        case "scroll":
            KeyCodes.postScroll(towardTop ? 1 : -1, base: mods.flags)
        case "keys":
            if let a = towardTop ? action.up : action.down {
                KeyCodes.postChord(mods: a.mods ?? [], key: a.key, base: mods.flags)
            }
        default: break
        }
    }
}
