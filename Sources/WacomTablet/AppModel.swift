// AppModel.swift — shared app state: the engine, the global calibration, and the
// switchable profiles. Edits apply and persist immediately.

import Foundation
import CoreGraphics
import Combine

final class AppModel: ObservableObject {
    let calibration: Calibration
    let mods = SharedModifiers()
    let injector: EventInjector
    let padHandler: PadHandler
    let engine: WacomEngine

    @Published var store: ProfileStore       // profiles + active selection
    @Published var penConfig: PenConfig       // global calibration (physical)
    @Published var ready = false

    var onCalibrate: (() -> Void)?
    var onProfilesChanged: (() -> Void)?      // lets the menu rebuild

    init() {
        let pen = PenConfig.load()
        let st = ProfileStore.load()
        penConfig = pen
        store = st
        calibration = Calibration(config: pen)
        injector = EventInjector(calibration: calibration, mods: mods)
        padHandler = PadHandler(config: st.active.pad, mods: mods)
        engine = WacomEngine(calibration: calibration, injector: injector, padHandler: padHandler)
        engine.onReady = { [weak self] in DispatchQueue.main.async { self?.ready = true } }
        injector.hoverSmoothing = pen.hoverSmoothing
        applyActiveProfile()
        engine.start()
    }

    // MARK: profiles

    var activeIndex: Int { store.profiles.firstIndex { $0.name == store.activeName } ?? 0 }
    var activeProfile: Profile { store.active }

    func applyActiveProfile() {
        let p = store.active
        padHandler.config = p.pad
        injector.pressureCurve = p.pressure
        injector.buttons = p.penButtons
    }

    /// Mutate the active profile, apply live, and persist.
    func updateActive(_ mutate: (inout Profile) -> Void) {
        let i = activeIndex
        guard store.profiles.indices.contains(i) else { return }
        mutate(&store.profiles[i])
        applyActiveProfile()
        store.save()
    }

    func switchProfile(_ name: String) {
        guard store.profiles.contains(where: { $0.name == name }) else { return }
        store.activeName = name
        applyActiveProfile()
        store.save()
        onProfilesChanged?()
    }

    /// New profile cloned from the current one (a good starting point).
    func addProfile(named base: String = "New Profile") {
        var name = base
        var n = 2
        while store.profiles.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        var p = store.active
        p.name = name
        store.profiles.append(p)
        store.activeName = name
        applyActiveProfile()
        store.save()
        onProfilesChanged?()
    }

    func deleteProfile(_ name: String) {
        guard store.profiles.count > 1 else { return }
        store.profiles.removeAll { $0.name == name }
        if store.activeName == name { store.activeName = store.profiles[0].name }
        applyActiveProfile()
        store.save()
        onProfilesChanged?()
    }

    func renameActive(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let i = activeIndex
        guard !trimmed.isEmpty, store.profiles.indices.contains(i),
              !store.profiles.contains(where: { $0.name == trimmed }) else { return }
        let old = store.profiles[i].name
        store.profiles[i].name = trimmed
        if store.activeName == old { store.activeName = trimmed }
        store.save()
        onProfilesChanged?()
    }

    // MARK: calibration (global)

    func applyPen() {
        calibration.config = penConfig
        calibration.pickDisplay()
        penConfig.save()
    }

    func setCalibration(affine: [Double]?) {
        penConfig.affine = affine
        applyPen()
    }

    /// Choose which display the pen maps to. nil = auto-detect (Cintiq heuristic,
    /// else main). Selecting a display stores its stable identity and re-picks.
    func setTargetDisplay(_ info: DisplayInfo?) {
        penConfig.displayVendor = info?.vendor
        penConfig.displayModel = info?.model
        penConfig.displaySerial = info?.serial
        // A stable identity supersedes any legacy/env index.
        penConfig.displayIndex = nil
        applyPen()
        objectWillChange.send()   // calibration.displayID/bounds changed, but aren't @Published
    }

    func setHoverSmoothing(_ v: Double) {
        penConfig.hoverSmoothing = v
        injector.hoverSmoothing = v
        penConfig.save()
    }
}
