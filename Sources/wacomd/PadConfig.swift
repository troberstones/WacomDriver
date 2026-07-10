// PadConfig.swift — maps ExpressKeys / Touch Strips to actions. JSON-configurable.
//
// Button IDs: L1..L8 (left ExpressKeys, top→bottom), R1..R8 (right), LT / RT
// (left / right center toggles).
//
// Loaded from (first that exists): $WACOM_CONFIG, ~/.config/wacomd/pad.json.
// Otherwise built-in defaults are used. Run with WACOM_DUMP_CONFIG=1 to print a
// template you can save and edit. Use WACOM_IDENTIFY=1 to see which physical
// control is which ID.

import Foundation

// One button action.
//   type "chord": press mods+key once (e.g. Cmd+Z).
//   type "hold":  hold `key` down while the button is held (e.g. shift, space).
struct KeyAction: Codable {
    var type: String
    var mods: [String]?
    var key: String
    var label: String?
}

// Touch Strip action.
//   mode "scroll": slide = scroll wheel.
//   mode "keys":   slide toward top sends `up`, toward bottom sends `down`.
struct StripAction: Codable {
    var mode: String
    var up: KeyAction?
    var down: KeyAction?
}

struct PadConfig: Codable {
    var buttons: [String: KeyAction]   // "L1".."R8", "LT", "RT"
    var leftStrip: StripAction
    var rightStrip: StripAction

    static func chord(_ mods: [String], _ key: String, _ label: String) -> KeyAction {
        KeyAction(type: "chord", mods: mods, key: key, label: label)
    }
    static func hold(_ key: String, _ label: String) -> KeyAction {
        KeyAction(type: "hold", mods: nil, key: key, label: label)
    }

    // Sensible, non-destructive defaults tuned for Krita/Photoshop. Remap freely.
    static let defaults = PadConfig(
        buttons: [
            // Left column. Bottom four (L5–L8) are the ZBrush-style modifiers;
            // top four are history + tools.
            "L1": chord(["cmd"], "z", "Undo"),
            "L2": chord(["cmd", "shift"], "z", "Redo"),
            "L3": chord([], "b", "Brush"),
            "L4": chord([], "e", "Eraser"),
            "L5": hold("space", "hold Space"),
            "L6": hold("shift", "hold Shift"),
            "L7": hold("control", "hold Ctrl"),
            "L8": hold("option", "hold Option"),
            // Right column: tools + view.
            "R1": chord([], "b", "Brush"),
            "R2": chord([], "x", "Swap colors"),
            "R3": chord([], "m", "Mirror view"),
            "R4": chord(["cmd"], "=", "Zoom in"),
            "R5": chord(["cmd"], "-", "Zoom out"),
            "R6": chord([], "5", "Reset zoom"),
            "R7": chord([], "[", "Brush size down"),
            "R8": chord([], "]", "Brush size up"),
            // Center toggles.
            "LT": chord([], "tab", "Toggle panels"),
            "RT": chord(["cmd"], "0", "Fit to view"),
        ],
        leftStrip: StripAction(mode: "scroll", up: nil, down: nil),
        rightStrip: StripAction(
            mode: "keys",
            up: chord(["cmd"], "=", "Zoom in"),
            down: chord(["cmd"], "-", "Zoom out"))
    )

    static func load() -> PadConfig {
        let env = ProcessInfo.processInfo.environment
        var paths: [String] = []
        if let p = env["WACOM_CONFIG"] { paths.append(p) }
        if let home = env["HOME"] { paths.append("\(home)/.config/wacomd/pad.json") }
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            do {
                let cfg = try JSONDecoder().decode(PadConfig.self, from: data)
                print("pad config loaded from \(path)")
                return cfg
            } catch {
                print("warning: failed to parse \(path): \(error). Using defaults.")
            }
        }
        return defaults
    }

    func jsonString() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
