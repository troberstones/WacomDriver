// wacomd — Milestone 1 pen daemon for the Cintiq 21UX (DTK-2100).
//
// Seizes the tablet, switches it to Wacom mode, parses pen packets, maps them to
// the Cintiq display, and injects pressure/tilt tablet events.
//
// Build: swift build -c release
// Run:   .build/release/wacomd
//   Needs Input Monitoring (to read HID) + Accessibility (to post events).
//   Env: WACOM_INVERT_X=1 / WACOM_INVERT_Y=1 to fix orientation,
//        WACOM_DISPLAY=<index> to force the target display,
//        WACOM_DEBUG=1 to log parsed samples.

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

let WACOM_VID = 0x056a
let DTK2100_PID = 0x00cc
let INPUT_BUFFER_SIZE = 64
let DEBUG = ProcessInfo.processInfo.environment["WACOM_DEBUG"] == "1"

// File-scope state, mutated only on the run-loop thread (HID callbacks fire there).
let calibration = Calibration()
nonisolated(unsafe) let injector = EventInjector(calibration: calibration)
nonisolated(unsafe) let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: INPUT_BUFFER_SIZE)
nonisolated(unsafe) var seizedDevice: IOHIDDevice?

func switchToWacomMode(_ device: IOHIDDevice) {
    let payload: [UInt8] = [0x02, 0x02]
    let status = payload.withUnsafeBufferPointer {
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 2, $0.baseAddress!, $0.count)
    }
    if status != kIOReturnSuccess {
        print(String(format: "warning: mode-switch feature report failed (0x%08x)", status))
    }
}

let inputReportCallback: IOHIDReportCallback = { _, result, _, _, _, report, reportLength in
    guard result == kIOReturnSuccess else { return }
    let len = Int(reportLength)
    guard len >= 10 else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: len))

    switch WacomProtocol.parse(bytes) {
    case .penData(let s):
        if DEBUG {
            print("pen x=\(s.x) y=\(s.y) p=\(s.pressure) tilt=(\(s.tiltX),\(s.tiltY)) b1=\(s.barrel1) b2=\(s.barrel2)")
        }
        injector.handle(s)
    case .proximityIn:
        injector.enterProximity()
    case .proximityOut:
        injector.leaveProximity()
    case .pad(let pad):
        if DEBUG { print("pad keys=0x\(String(pad.keyBits, radix: 16)) strip1=\(pad.strip1) strip2=\(pad.strip2)") }
        // ExpressKeys / Touch Strips: wired up in Milestone 3.
    case .other:
        break
    }
}

let matchCallback: IOHIDDeviceCallback = { _, _, _, device in
    let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    guard openStatus == kIOReturnSuccess else {
        print(String(format: "seize failed (0x%08x). Grant Input Monitoring / try sudo.", openStatus))
        return
    }
    seizedDevice = device
    IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, INPUT_BUFFER_SIZE, inputReportCallback, nil)
    switchToWacomMode(device)
    print("Tablet seized and switched to Wacom mode. Pen is live.")
}

func shutdown() {
    injector.leaveProximity()
    if let d = seizedDevice { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) }
    print("\nwacomd stopped.")
    exit(0)
}

// Clean shutdown so we release the device and post proximity-out.
nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { shutdown() }
    src.resume()
    signalSources.append(src) // keep the source alive for the process lifetime
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: WACOM_VID,
    kIOHIDProductIDKey as String: DTK2100_PID,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
print(String(format: "wacomd starting (IOHIDManagerOpen 0x%08x)", openStatus))
print("Target display \(calibration.displayID): \(Int(calibration.screenBounds.width))x\(Int(calibration.screenBounds.height)) at (\(Int(calibration.screenBounds.minX)),\(Int(calibration.screenBounds.minY)))")
print("Waiting for DTK-2100…  (Ctrl-C to stop)")

CFRunLoopRun()
