// Daemon.swift — headless mode (WacomTablet --headless). Same driver core as the
// GUI, no UI. Suitable for a LaunchAgent.

import Foundation
import IOKit.hid
import CoreGraphics

func runHeadless() -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)

    let env = ProcessInfo.processInfo.environment
    let calibration = Calibration()
    let mods = SharedModifiers()
    let profile = ProfileStore.load().active
    let injector = EventInjector(calibration: calibration, mods: mods)
    injector.pressureCurve = profile.pressure
    injector.buttons = profile.penButtons
    injector.hoverSmoothing = calibration.config.hoverSmoothing
    let padHandler = PadHandler(config: profile.pad, mods: mods)
    let engine = WacomEngine(calibration: calibration, injector: injector, padHandler: padHandler)
    engine.debug = env["WACOM_DEBUG"] == "1"
    engine.suppressInjection = env["WACOM_IDENTIFY"] == "1"
    engine.onReady = { print("Tablet seized and switched to Wacom mode. Pen is live.") }

    var signalSources: [DispatchSourceSignal] = []
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { engine.stop(); print("\nstopped."); exit(0) }
        src.resume()
        signalSources.append(src)
    }

    print("WacomTablet starting (headless)…")
    print("Target display \(calibration.displayID): \(Int(calibration.screenBounds.width))x\(Int(calibration.screenBounds.height))")
    engine.start()
    print("Waiting for DTK-2100…  (Ctrl-C to stop)")
    withExtendedLifetime(signalSources) { CFRunLoopRun() }
    fatalError("run loop exited")
}
