// Calibration.swift — map raw tablet coordinates onto the Cintiq's screen rect.
//
// Uses a 4-point affine calibration when present (config.affine), else a linear
// map from the tablet's logical range to the target display's size. The affine
// (and the linear map) produce DISPLAY-LOCAL points (0…width, 0…height); we add
// the display's live global origin here, so a calibration survives the Cintiq
// moving in the display arrangement — main, mirrored, or extended secondary.
//
// The target display is chosen by a stable identity (vendor/model/serial the
// user picked in Settings), then a "looks like a Cintiq" heuristic, then main.
// We re-pick whenever the display arrangement changes.
//
// Env overrides still work: WACOM_INVERT_X/Y=1, WACOM_DISPLAY=<index>.

import Foundation
import CoreGraphics
import AppKit

/// A connected display, with the stable identity we persist to re-find it.
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let name: String
    let bounds: CGRect       // global, top-left origin (points)
    let isMain: Bool
    let isMirrored: Bool

    /// A one-line label for the Settings picker.
    var menuLabel: String {
        let dims = "\(Int(bounds.width))×\(Int(bounds.height))"
        var tags = [String]()
        if isMain { tags.append("main") }
        if isMirrored { tags.append("mirrored") }
        let suffix = tags.isEmpty ? "" : " — \(tags.joined(separator: ", "))"
        return "\(name)  (\(dims))\(suffix)"
    }
}

final class Calibration {
    var config: PenConfig
    private(set) var screenBounds: CGRect = .zero
    private(set) var displayID: CGDirectDisplayID = 0
    private var reconfigRegistered = false

    init(config: PenConfig = .load()) {
        self.config = config
        // Env vars take precedence over the file (handy for quick testing).
        let env = ProcessInfo.processInfo.environment
        if env["WACOM_INVERT_X"] == "1" { self.config.invertX = true }
        if env["WACOM_INVERT_Y"] == "1" { self.config.invertY = true }
        if let s = env["WACOM_DISPLAY"], let i = Int(s) { self.config.displayIndex = i }
        pickDisplay()
        registerReconfigCallback()
    }

    deinit {
        if reconfigRegistered {
            CGDisplayRemoveReconfigurationCallback(Calibration.reconfigCallback,
                                                   Unmanaged.passUnretained(self).toOpaque())
        }
    }

    /// Map a raw tablet point to a global screen point (top-left origin).
    func screenPoint(x: Int, y: Int) -> CGPoint {
        let local: CGPoint
        if let a = config.affine, a.count == 6 {
            let rx = Double(x), ry = Double(y)
            // Affine maps raw → display-local (0…width, 0…height).
            local = CGPoint(x: a[0] * rx + a[1] * ry + a[2],
                            y: a[3] * rx + a[4] * ry + a[5])
        } else {
            // Linear fallback across the display's size.
            var fx = min(max(Double(x) / config.tabletMaxX, 0), 1)
            var fy = min(max(Double(y) / config.tabletMaxY, 0), 1)
            if config.invertX { fx = 1 - fx }
            if config.invertY { fy = 1 - fy }
            local = CGPoint(x: fx * screenBounds.width, y: fy * screenBounds.height)
        }
        // Add the display's live global origin so the point lands on the Cintiq
        // wherever macOS currently places it (mirror, main, or extended).
        return CGPoint(x: screenBounds.minX + local.x, y: screenBounds.minY + local.y)
    }

    /// The target display's corner points (top-left origin) for calibration UI.
    var displayCorners: (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint) {
        let b = screenBounds
        return (CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY))
    }

    func pickDisplay() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        if let idx = config.displayIndex, idx >= 0, idx < ids.count {
            // Explicit index (env WACOM_DISPLAY or legacy config) wins.
            displayID = ids[idx]
        } else if let matched = matchStoredDisplay(in: ids) {
            // The display the user picked in Settings, re-found by identity.
            displayID = matched
        } else if let cintiq = ids.first(where: { Calibration.looksLikeCintiq($0) }) {
            // Zero-config auto-detect for the common single-pen-display case.
            displayID = cintiq
        } else {
            displayID = CGMainDisplayID()
        }
        screenBounds = CGDisplayBounds(displayID)
    }

    /// Match the persisted (vendor, model, serial) identity to a live display.
    private func matchStoredDisplay(in ids: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        guard let v = config.displayVendor,
              let m = config.displayModel,
              let s = config.displaySerial else { return nil }
        return ids.first {
            CGDisplayVendorNumber($0) == v &&
            CGDisplayModelNumber($0) == m &&
            CGDisplaySerialNumber($0) == s
        }
    }

    // MARK: display enumeration (for Settings)

    /// All currently active displays, with the identity we persist and a name.
    static func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let main = CGMainDisplayID()
        return ids.map { id in
            DisplayInfo(id: id,
                        vendor: CGDisplayVendorNumber(id),
                        model: CGDisplayModelNumber(id),
                        serial: CGDisplaySerialNumber(id),
                        name: displayName(id),
                        bounds: CGDisplayBounds(id),
                        isMain: id == main,
                        isMirrored: CGDisplayIsInMirrorSet(id) != 0)
        }
    }

    /// A human-readable name for a display (NSScreen.localizedName), with a fallback.
    static func displayName(_ id: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            let n = screen.localizedName
            if !n.isEmpty { return n }
        }
        let b = CGDisplayBounds(id)
        return "Display \(id) (\(Int(b.width))×\(Int(b.height)))"
    }

    /// Heuristic auto-detect: a Cintiq by name, else the DTK-2100's 1600×1200.
    static func looksLikeCintiq(_ id: CGDirectDisplayID) -> Bool {
        let name = displayName(id).lowercased()
        if name.contains("cintiq") || name.contains("dtk") || name.contains("wacom") {
            return true
        }
        let b = CGDisplayBounds(id)
        return Int(b.width) == 1600 && Int(b.height) == 1200
    }

    // MARK: live display re-arrangement

    private func registerReconfigCallback() {
        guard !reconfigRegistered else { return }
        CGDisplayRegisterReconfigurationCallback(Calibration.reconfigCallback,
                                                 Unmanaged.passUnretained(self).toOpaque())
        reconfigRegistered = true
    }

    // C callback: fires on any display add/remove/move/mirror change. We re-pick
    // the target so screenBounds tracks the Cintiq's current position.
    private static let reconfigCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        // Ignore the "begin" notification; act once the change has settled.
        if flags.contains(.beginConfigurationFlag) { return }
        guard let userInfo = userInfo else { return }
        let me = Unmanaged<Calibration>.fromOpaque(userInfo).takeUnretainedValue()
        me.pickDisplay()
    }
}
