// wacomd — headless pen daemon for the Cintiq 21UX (DTK-2100).
//
// Build: swift build -c release
// Run:   .build/release/wacomd
//   Needs Input Monitoring (to read HID) + Accessibility (to post events).
//   Env: WACOM_INVERT_X/Y=1 orientation, WACOM_DISPLAY=<index> target display,
//        WACOM_DEBUG=1 log samples, WACOM_IDENTIFY=1 print pad control IDs,
//        WACOM_DUMP_CONFIG=1 print a config template and exit.

import Foundation
import IOKit.hid
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

let env = ProcessInfo.processInfo.environment
if env["WACOM_DUMP_CONFIG"] == "1" {
    print(PadConfig.defaults.jsonString())
    exit(0)
}

let calibration = Calibration()
let mods = SharedModifiers()
let injector = EventInjector(calibration: calibration, mods: mods)
let padHandler = PadHandler(config: PadConfig.load(), mods: mods)
let engine = WacomEngine(calibration: calibration, injector: injector, padHandler: padHandler)
engine.debug = env["WACOM_DEBUG"] == "1"
engine.suppressInjection = env["WACOM_IDENTIFY"] == "1"
engine.onReady = { print("Tablet seized and switched to Wacom mode. Pen is live.") }

// Clean shutdown so we release the device and post proximity-out.
nonisolated(unsafe) let engineRef = engine
nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { engineRef.stop(); print("\nwacomd stopped."); exit(0) }
    src.resume()
    signalSources.append(src)
}

print("wacomd starting…")
print("Target display \(calibration.displayID): \(Int(calibration.screenBounds.width))x\(Int(calibration.screenBounds.height)) at (\(Int(calibration.screenBounds.minX)),\(Int(calibration.screenBounds.minY)))")
engine.start()
print("Waiting for DTK-2100…  (Ctrl-C to stop)")
CFRunLoopRun()
