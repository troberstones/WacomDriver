// Calibration.swift — map raw tablet coordinates onto the Cintiq's screen rect.
//
// Uses a 4-point affine calibration when present (config.affine), else a linear
// map from the tablet's logical range to the target display's bounds. Both emit
// points in the global top-left-origin space CGEvent uses.
//
// Env overrides still work: WACOM_INVERT_X/Y=1, WACOM_DISPLAY=<index>.

import Foundation
import CoreGraphics
import AppKit

final class Calibration {
    var config: PenConfig
    private(set) var screenBounds: CGRect = .zero
    private(set) var displayID: CGDirectDisplayID = 0

    init(config: PenConfig = .load()) {
        self.config = config
        // Env vars take precedence over the file (handy for quick testing).
        let env = ProcessInfo.processInfo.environment
        if env["WACOM_INVERT_X"] == "1" { self.config.invertX = true }
        if env["WACOM_INVERT_Y"] == "1" { self.config.invertY = true }
        if let s = env["WACOM_DISPLAY"], let i = Int(s) { self.config.displayIndex = i }
        pickDisplay()
    }

    /// Map a raw tablet point to a global screen point (top-left origin).
    func screenPoint(x: Int, y: Int) -> CGPoint {
        if let a = config.affine, a.count == 6 {
            let rx = Double(x), ry = Double(y)
            return CGPoint(x: a[0] * rx + a[1] * ry + a[2],
                           y: a[3] * rx + a[4] * ry + a[5])
        }
        // Linear fallback across the display bounds.
        var fx = min(max(Double(x) / config.tabletMaxX, 0), 1)
        var fy = min(max(Double(y) / config.tabletMaxY, 0), 1)
        if config.invertX { fx = 1 - fx }
        if config.invertY { fy = 1 - fy }
        return CGPoint(x: screenBounds.minX + fx * screenBounds.width,
                       y: screenBounds.minY + fy * screenBounds.height)
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
            displayID = ids[idx]
        } else if let cintiq = ids.first(where: { CGDisplayPixelsWide($0) == 1600 && CGDisplayPixelsHigh($0) == 1200 }) {
            displayID = cintiq
        } else {
            displayID = CGMainDisplayID()
        }
        screenBounds = CGDisplayBounds(displayID)
    }
}
