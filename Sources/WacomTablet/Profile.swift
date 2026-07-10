// Profile.swift — named, switchable configuration bundles (one per app/workflow).
//
// A profile holds the app-specific settings: ExpressKey/strip mapping, pen-button
// mapping, and pressure. Calibration is physical, so it stays global (PenConfig).
// Stored in ~/.config/wacomd/profiles.json.

import Foundation

// Pen tip / barrel buttons → mouse button ("left" | "right" | "middle" | "none").
struct PenButtons: Codable, Equatable {
    var tip = "left"
    var barrel1 = "right"
    var barrel2 = "middle"
}

struct Profile: Codable, Identifiable {
    var name: String
    var pad: PadConfig
    var penButtons: PenButtons
    var pressureGamma: Double
    var pressure: PressureCurve

    var id: String { name }

    static func standard(_ name: String, pad: PadConfig = .defaults) -> Profile {
        Profile(name: name, pad: pad, penButtons: PenButtons(),
                pressureGamma: 1.0, pressure: .linear)
    }
}

struct ProfileStore: Codable {
    var activeName: String
    var profiles: [Profile]

    var active: Profile {
        profiles.first { $0.name == activeName } ?? profiles.first ?? .standard("Default")
    }

    static func path() -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "."
        return "\(home)/.config/wacomd/profiles.json"
    }

    static func load() -> ProfileStore {
        if let data = FileManager.default.contents(atPath: path()),
           let store = try? JSONDecoder().decode(ProfileStore.self, from: data),
           !store.profiles.isEmpty {
            return store
        }
        // First run: seed a Default profile from any existing pad.json so prior
        // ExpressKey settings carry over.
        let def = Profile.standard("Default", pad: PadConfig.load())
        return ProfileStore(activeName: def.name, profiles: [def])
    }

    func save() {
        let dir = (ProfileStore.path() as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: URL(fileURLWithPath: ProfileStore.path()))
        }
    }
}
