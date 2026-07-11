// EventInjector.swift — turn parsed pen samples into macOS tablet events.
//
// Uses the public CGEvent tablet fields (CGEventTypes.h). Apps read pressure
// from NSEvent, which is populated from these fields. Needs Accessibility
// permission to post.

import Foundation
import CoreGraphics

final class EventInjector {
    private let cal: Calibration
    // Wacom-compatible sentinel device id (matches OpenTabletDriver). Shared by
    // the proximity-enter event (which registers the tool in Qt/Krita) and every
    // subsequent pointer event so apps link them.
    private let deviceID: Int64 = 5303613955435230461
    private let vendorID: Int64 = 0x056a
    private let tipThreshold = 6          // pressure above this == tip touching

    // What the tool can report — apps read this from the proximity event to
    // decide whether to honour pressure/tilt. Wacom's real bit layout (matches
    // OpenTabletDriver): note pressure is 0x400, NOT 0x40. Total = 0x5C7.
    private let capabilityMask: Int64 =
        0x001 | // device id
        0x002 | // absolute X
        0x004 | // absolute Y
        0x040 | // buttons
        0x080 | // tilt X
        0x100 | // tilt Y
        0x400   // pressure

    // NX tablet pointer types (IOLLEvent.h): 1 = pen, 3 = eraser.
    private let pointerTypePen: Int64 = 1
    private let pointerTypeEraser: Int64 = 3
    private let vendorPointerTypePen: Int64 = 0x0802   // Wacom Grip Pen
    private let vendorPointerTypeEraser: Int64 = 0x082a // Wacom eraser

    // Button state so we emit clean down/up transitions.
    private var tipDown = false
    private var barrel1Down = false
    private var barrel2Down = false
    private var inProximity = false
    private var currentTool: WacomTool = .pen
    private var lastPoint = CGPoint.zero
    private var smoother = PointSmoother(amount: 0)

    private let mods: SharedModifiers

    // Live-swappable from the active profile.
    var pressureCurve = PressureCurve.linear
    var buttons = PenButtons()
    /// Cursor smoothing strength (0…1) applied only while hovering. 0 = off.
    var hoverSmoothing: Double = 0 {
        didSet { smoother.setAmount(hoverSmoothing) }
    }

    init(calibration: Calibration, mods: SharedModifiers) {
        self.cal = calibration
        self.mods = mods
    }

    // pen-button name -> mouse button (nil = "none").
    private func cgButton(_ name: String) -> CGMouseButton? {
        switch name.lowercased() {
        case "left":            return .left
        case "right":           return .right
        case "middle", "center": return .center
        default:                return nil
        }
    }

    private func draggedType(_ b: CGMouseButton) -> CGEventType {
        switch b {
        case .left:  return .leftMouseDragged
        case .right: return .rightMouseDragged
        default:     return .otherMouseDragged
        }
    }

    private func maskBit(_ b: CGMouseButton?) -> Int64 {
        switch b { case .left: return 1; case .right: return 2; case .center: return 4; default: return 0 }
    }

    // MARK: proximity

    func enterProximity(tool: WacomTool = .pen) {
        guard !inProximity else { return }
        inProximity = true
        currentTool = tool
        smoother.reset()
        postProximity(entering: true, at: lastPoint)
    }

    func leaveProximity() {
        guard inProximity else { return }
        // Release anything still held (set state false BEFORE posting the up).
        if tipDown { tipDown = false; if let b = cgButton(buttons.tip) { setButton(b, down: false, at: lastPoint, pressure: 0) } }
        if barrel1Down { barrel1Down = false; if let b = cgButton(buttons.barrel1) { setButton(b, down: false, at: lastPoint, pressure: 0) } }
        if barrel2Down { barrel2Down = false; if let b = cgButton(buttons.barrel2) { setButton(b, down: false, at: lastPoint, pressure: 0) } }
        inProximity = false
        postProximity(entering: false, at: lastPoint)
    }

    // MARK: pen data

    func handle(_ s: PenSample) {
        if !inProximity { enterProximity() }

        let raw = cal.screenPoint(x: s.x, y: s.y)
        let pressure = pressureCurve.apply(Double(s.pressure) / Double(WacomProtocol.pressureMax))
        let tipNow = s.pressure > tipThreshold

        // Smooth only while hovering; a live stroke uses the raw points so the
        // ink tracks the nib exactly. Reset on tip-down so the next hover starts
        // clean (no lag catching up from the last stroke).
        let p: CGPoint
        if tipNow {
            smoother.reset()
            p = raw
        } else {
            p = smoother.filter(raw, at: CFAbsoluteTimeGetCurrent())
        }
        lastPoint = p

        // Each pen button maps to a configurable mouse button. Update the pen
        // state BEFORE posting (the event reads the state via currentButtonMask,
        // so we must not hold an exclusive inout access across the post).
        if tipNow != tipDown {
            tipDown = tipNow
            if let b = cgButton(buttons.tip) { setButton(b, down: tipNow, at: p, pressure: tipNow ? pressure : 0, sample: s) }
        }
        if s.barrel1 != barrel1Down {
            barrel1Down = s.barrel1
            if let b = cgButton(buttons.barrel1) { setButton(b, down: s.barrel1, at: p, pressure: 0, sample: s) }
        }
        if s.barrel2 != barrel2Down {
            barrel2Down = s.barrel2
            if let b = cgButton(buttons.barrel2) { setButton(b, down: s.barrel2, at: p, pressure: 0, sample: s) }
        }

        // Motion: drag with the highest-priority held button (tip first), else move.
        if tipDown, let b = cgButton(buttons.tip) {
            postMouse(type: draggedType(b), button: b, at: p, pressure: pressure, sample: s)
        } else if barrel1Down, let b = cgButton(buttons.barrel1) {
            postMouse(type: draggedType(b), button: b, at: p, pressure: 0, sample: s)
        } else if barrel2Down, let b = cgButton(buttons.barrel2) {
            postMouse(type: draggedType(b), button: b, at: p, pressure: 0, sample: s)
        } else {
            postMouse(type: .mouseMoved, button: .left, at: p, pressure: 0, sample: s)
        }
    }


    // MARK: CGEvent construction

    private func setButton(_ button: CGMouseButton, down: Bool, at p: CGPoint, pressure: Double, sample: PenSample? = nil) {
        let type: CGEventType
        switch button {
        case .left:  type = down ? .leftMouseDown  : .leftMouseUp
        case .right: type = down ? .rightMouseDown : .rightMouseUp
        default:     type = down ? .otherMouseDown : .otherMouseUp
        }
        postMouse(type: type, button: button, at: p, pressure: pressure, sample: sample)
    }

    private func currentButtonMask() -> Int64 {
        var m: Int64 = 0
        if tipDown { m |= maskBit(cgButton(buttons.tip)) }
        if barrel1Down { m |= maskBit(cgButton(buttons.barrel1)) }
        if barrel2Down { m |= maskBit(cgButton(buttons.barrel2)) }
        return m
    }

    private func postMouse(type: CGEventType, button: CGMouseButton, at p: CGPoint, pressure: Double, sample: PenSample?) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        // NSEvent.pressure reads mouseEventPressure for a mouse-type event — set
        // it too, or apps see a constant 1.0 while the tip "button" is held.
        e.setDoubleValueField(.mouseEventPressure, value: pressure)
        // Subtype BEFORE the tablet fields (CGEvent stores them in a
        // type-dependent union).
        e.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        e.setIntegerValueField(.tabletEventPointButtons, value: currentButtonMask())
        e.setIntegerValueField(.tabletEventDeviceID, value: deviceID)
        e.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        if let s = sample {
            e.setDoubleValueField(.tabletEventTiltX, value: Double(s.tiltX) / 64.0)
            e.setDoubleValueField(.tabletEventTiltY, value: -Double(s.tiltY) / 64.0)
        }
        // Stamp held modifiers (from ExpressKeys) onto pen events so hold-Shift
        // affects drawing, and so a chord's modifier never lingers.
        e.flags = mods.flags
        e.post(tap: .cghidEventTap)
    }

    private func postProximity(entering: Bool, at p: CGPoint) {
        guard let e = CGEvent(source: nil) else { return }
        // A DEDICATED tablet-proximity event (not a mouse event with a tablet
        // subtype). Only this reaches Qt's tabletProximity: handler, which
        // registers the tool so later pointer events become QTabletEvents.
        e.type = .tabletProximity
        e.location = p
        e.setIntegerValueField(.tabletProximityEventVendorID, value: vendorID)
        e.setIntegerValueField(.tabletProximityEventTabletID, value: 1)
        e.setIntegerValueField(.tabletProximityEventPointerID, value: 0)
        e.setIntegerValueField(.tabletProximityEventDeviceID, value: deviceID)
        e.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 0)
        let isEraser = currentTool == .eraser
        e.setIntegerValueField(.tabletProximityEventVendorPointerType,
                               value: isEraser ? vendorPointerTypeEraser : vendorPointerTypePen)
        e.setIntegerValueField(.tabletProximityEventVendorPointerSerialNumber, value: 1)
        e.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: 1)
        e.setIntegerValueField(.tabletProximityEventCapabilityMask, value: capabilityMask)
        // Pointer type is what apps read to switch to the eraser tool.
        e.setIntegerValueField(.tabletProximityEventPointerType,
                               value: isEraser ? pointerTypeEraser : pointerTypePen)
        e.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        e.post(tap: .cghidEventTap)
    }
}
