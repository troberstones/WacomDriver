// KeyCodes.swift — post keystrokes / scroll for ExpressKey & Touch Strip actions.

import Foundation
import CoreGraphics

// Held-modifier state shared between the pad handler (which sets it) and the pen
// injector (which stamps it onto every event). Representing modifiers as flags
// on every event — rather than as pressed modifier keycodes — means they never
// get stuck: the next event that carries the current flag set supersedes them.
final class SharedModifiers {
    var flags: CGEventFlags = []
}

enum KeyCodes {
    static func modifierMask(_ name: String) -> CGEventFlags? {
        switch name.lowercased() {
        case "cmd", "command", "meta": return .maskCommand
        case "shift":                  return .maskShift
        case "ctrl", "control":        return .maskControl
        case "alt", "option", "opt":   return .maskAlternate
        default: return nil
        }
    }

    static func flags(_ mods: [String]) -> CGEventFlags {
        mods.reduce(into: CGEventFlags()) { if let m = modifierMask($1) { $0.insert(m) } }
    }

    // Virtual key code for a modifier flag (so we can emit real flagsChanged).
    static func modifierKeyCode(_ mask: CGEventFlags) -> CGKeyCode? {
        switch mask {
        case .maskCommand:   return 55
        case .maskShift:     return 56
        case .maskAlternate: return 58
        case .maskControl:   return 59
        default: return nil
        }
    }

    private static func postRaw(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }

    /// Press or release a modifier as a real key event (updates flagsChanged).
    /// `base` is the modifier set that should remain after this event.
    static func postModifier(_ mask: CGEventFlags, down: Bool, base: CGEventFlags) {
        guard let code = modifierKeyCode(mask) else { return }
        postRaw(code, down, base)
    }

    // Name -> macOS virtual key code.
    static func virtualKey(_ name: String) -> CGKeyCode? {
        let map: [String: CGKeyCode] = [
            "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,
            "b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
            "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,
            "-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,"i":34,"p":35,
            "l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,
            "space":49,"tab":48,"return":36,"delete":51,"escape":53,
            "left":123,"right":124,"down":125,"up":126,
        ]
        return map[name.lowercased()]
    }

    /// One-shot chord, e.g. mods=["cmd"], key="z". The chord's own modifiers are
    /// pressed and released as real key events (bracketing the key) on top of any
    /// currently-held modifiers in `base`, so nothing is ever left stuck.
    static func postChord(mods: [String], key: String, base: CGEventFlags) {
        guard let code = virtualKey(key) else { return }
        let chordMasks = mods.compactMap { modifierMask($0) }
        var f = base
        for m in chordMasks where !f.contains(m) { f.insert(m); postModifier(m, down: true, base: f) }
        postRaw(code, true, f)
        postRaw(code, false, f)
        for m in chordMasks.reversed() where base.contains(m) == false {
            f.remove(m); postModifier(m, down: false, base: f)
        }
    }

    /// Press/release a single non-modifier key (e.g. Space for pan).
    static func postKey(_ key: String, down: Bool, base: CGEventFlags) {
        guard let code = virtualKey(key) else { return }
        postRaw(code, down, base)
    }

    /// Vertical scroll wheel tick (+ up / - down).
    static func postScroll(_ lines: Int32, base: CGEventFlags) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                        wheel1: lines, wheel2: 0, wheel3: 0)
        e?.flags = base
        e?.post(tap: .cghidEventTap)
    }
}
