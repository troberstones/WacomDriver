// AppModel.swift — shared app state: owns the engine and the live config, and
// applies edits from the settings UI immediately.

import Foundation
import CoreGraphics
import Combine

final class AppModel: ObservableObject {
    let calibration: Calibration
    let mods = SharedModifiers()
    let injector: EventInjector
    let padHandler: PadHandler
    let engine: WacomEngine

    @Published var padConfig: PadConfig
    @Published var penConfig: PenConfig
    @Published var ready = false

    /// Set by the AppDelegate so the settings window can launch calibration.
    var onCalibrate: (() -> Void)?

    init() {
        let pen = PenConfig.load()
        let pad = PadConfig.load()
        penConfig = pen
        padConfig = pad
        calibration = Calibration(config: pen)
        injector = EventInjector(calibration: calibration, mods: mods)
        padHandler = PadHandler(config: pad, mods: mods)
        engine = WacomEngine(calibration: calibration, injector: injector, padHandler: padHandler)
        engine.onReady = { [weak self] in
            DispatchQueue.main.async { self?.ready = true }
        }
        engine.start()
    }

    // Apply + persist edits. Everything runs on the main run loop, same as the
    // engine callbacks, so direct mutation is safe.

    func applyPad() {
        padHandler.config = padConfig
        padConfig.save()
    }

    func applyPen() {
        calibration.config = penConfig
        calibration.pickDisplay()
        penConfig.save()
    }

    /// Store a freshly-solved calibration and apply it live.
    func setCalibration(affine: [Double]?) {
        penConfig.affine = affine
        applyPen()
    }
}
