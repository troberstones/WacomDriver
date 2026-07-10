// Calibration.swift — map raw tablet coordinates onto the Cintiq's screen rect.
//
// M1 uses a simple linear map from the tablet's logical range to the target
// display's bounds. The logical maxima match linuxwacom's Cintiq 21UX2 entry.
// Orientation can be flipped at runtime via env vars without a rebuild:
//   WACOM_INVERT_X=1  WACOM_INVERT_Y=1  WACOM_DISPLAY=<index>

import Foundation
import CoreGraphics
import AppKit

struct Calibration {
    // Full logical range of the DTK-2100 digitizer (linuxwacom Cintiq 21UX2).
    var tabletMaxX = 87200.0
    var tabletMaxY = 65600.0
    var invertX = ProcessInfo.processInfo.environment["WACOM_INVERT_X"] == "1"
    var invertY = ProcessInfo.processInfo.environment["WACOM_INVERT_Y"] == "1"

    // Target display bounds in the global top-left-origin point space that
    // CGEvent uses.
    let screenBounds: CGRect
    let displayID: CGDirectDisplayID

    init() {
        (displayID, screenBounds) = Calibration.pickDisplay()
    }

    /// Map a raw tablet point to a global screen point (top-left origin).
    func screenPoint(x: Int, y: Int) -> CGPoint {
        var fx = Double(x) / tabletMaxX
        var fy = Double(y) / tabletMaxY
        fx = min(max(fx, 0), 1)
        fy = min(max(fy, 0), 1)
        if invertX { fx = 1 - fx }
        if invertY { fy = 1 - fy }
        return CGPoint(x: screenBounds.minX + fx * screenBounds.width,
                       y: screenBounds.minY + fy * screenBounds.height)
    }

    /// Choose the Cintiq: prefer a 1600x1200 display, else WACOM_DISPLAY index,
    /// else the main display.
    private static func pickDisplay() -> (CGDirectDisplayID, CGRect) {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        if let idxStr = ProcessInfo.processInfo.environment["WACOM_DISPLAY"],
           let idx = Int(idxStr), idx >= 0, idx < ids.count {
            let id = ids[idx]
            return (id, CGDisplayBounds(id))
        }
        for id in ids where CGDisplayPixelsWide(id) == 1600 && CGDisplayPixelsHigh(id) == 1200 {
            return (id, CGDisplayBounds(id))
        }
        let main = CGMainDisplayID()
        return (main, CGDisplayBounds(main))
    }
}
