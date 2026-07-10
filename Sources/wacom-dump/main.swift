// wacom-dump — Milestone 0a feasibility spike
//
// Seizes the Cintiq 21UX (DTK-2100) HID interface away from macOS's built-in
// mouse driver, sends candidate "Wacom mode" feature reports, and hex-dumps
// every raw input report that arrives. Use it to confirm the tablet emits
// 10-byte pressure packets and to reverse the exact byte layout by watching the
// bytes change as you move / press the pen.
//
// Build:  swift build
// Run:    sudo .build/debug/wacom-dump        (sudo helps the seize succeed)
//
// The terminal app running this needs Input Monitoring permission
// (System Settings ▸ Privacy & Security ▸ Input Monitoring).

import Foundation
import IOKit
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0) // line-buffered so output survives if the run is cut short

let WACOM_VID: Int = 0x056a
let DTK2100_PID: Int = 0x00cc
let INPUT_BUFFER_SIZE = 64

// Candidate mode-switch feature reports to try, most-likely first.
// Format: (reportID, payload bytes). The classic USB-Wacom switch is feature
// report 2 with value 2. We fire each and watch which one makes 10-byte packets
// start flowing.
let modeSwitchCandidates: [(id: Int, bytes: [UInt8])] = [
    (2, [0x02, 0x02]),
    (2, [0x02]),
    (2, [0x02, 0x00]),
]

// Persisted buffer the input-report callback writes into. `nonisolated(unsafe)`
// because IOKit calls the C callback on our run loop thread; there is no
// concurrent access.
nonisolated(unsafe) let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: INPUT_BUFFER_SIZE)
nonisolated(unsafe) var reportCount = 0

func hex(_ ptr: UnsafePointer<UInt8>, _ len: Int) -> String {
    (0..<len).map { String(format: "%02x", ptr[$0]) }.joined(separator: " ")
}

// Fired for every raw input report once the device is in Wacom mode.
let inputReportCallback: IOHIDReportCallback = { _, result, _, type, reportID, report, reportLength in
    guard result == kIOReturnSuccess else { return }
    reportCount += 1
    let len = Int(reportLength)
    print(String(format: "[#%05d] id=%2d len=%2d  %@",
                 reportCount, reportID, len, hex(report, len)))
}

func trySwitchToWacomMode(_ device: IOHIDDevice) {
    for candidate in modeSwitchCandidates {
        let payload = candidate.bytes
        let status = payload.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature,
                                 CFIndex(candidate.id), buf.baseAddress!, buf.count)
        }
        let ok = status == kIOReturnSuccess
        print(String(format: "  mode-switch feature id=%d %@ -> %@ (0x%08x)",
                     candidate.id,
                     payload.map { String(format: "%02x", $0) }.joined(),
                     ok ? "OK" : "FAILED", status))
    }
}

// Fired when a matching DTK-2100 appears.
let matchCallback: IOHIDDeviceCallback = { _, _, _, device in
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    print("Matched device: \(product)")

    let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    if openStatus == kIOReturnSuccess {
        print("Seized device (exclusive access).")
    } else {
        print(String(format: "SEIZE FAILED (0x%08x) — try running with sudo, and grant Input Monitoring.", openStatus))
        // Keep going: a non-seized open may still deliver reports on some setups.
    }

    IOHIDDeviceRegisterInputReportCallback(
        device, reportBuffer, INPUT_BUFFER_SIZE, inputReportCallback, nil)

    print("Sending mode-switch candidates…")
    trySwitchToWacomMode(device)
    print("Now move the pen and press. Raw reports below (Ctrl-C to stop):\n")
}

// --- main ---
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: WACOM_VID,
    kIOHIDProductIDKey as String: DTK2100_PID,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openManagerStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
print(String(format: "IOHIDManagerOpen (seize) -> 0x%08x", openManagerStatus))
print("Waiting for DTK-2100 (VID 0x056a / PID 0x00cc)…")

CFRunLoopRun()
