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
    private let vendorPointerType: Int64 = 0x802 // Wacom general stylus
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

    // Button state so we emit clean down/up transitions.
    private var tipDown = false
    private var barrel1Down = false
    private var barrel2Down = false
    private var inProximity = false
    private var lastPoint = CGPoint.zero

    private let mods: SharedModifiers

    init(calibration: Calibration, mods: SharedModifiers) {
        self.cal = calibration
        self.mods = mods
    }

    // MARK: proximity

    func enterProximity() {
        guard !inProximity else { return }
        inProximity = true
        postProximity(entering: true, at: lastPoint)
    }

    func leaveProximity() {
        guard inProximity else { return }
        // Release anything still held.
        if tipDown { setButton(.left, down: false, at: lastPoint, pressure: 0) ; tipDown = false }
        if barrel1Down { setButton(.right, down: false, at: lastPoint, pressure: 0); barrel1Down = false }
        if barrel2Down { setButton(.center, down: false, at: lastPoint, pressure: 0); barrel2Down = false }
        inProximity = false
        postProximity(entering: false, at: lastPoint)
    }

    // MARK: pen data

    func handle(_ s: PenSample) {
        if !inProximity { enterProximity() }

        let p = cal.screenPoint(x: s.x, y: s.y)
        lastPoint = p
        let pressure = cal.config.pressure.apply(Double(s.pressure) / Double(WacomProtocol.pressureMax))
        let tipNow = s.pressure > tipThreshold

        // Tip transitions (primary / drawing button).
        if tipNow && !tipDown {
            tipDown = true
            setButton(.left, down: true, at: p, pressure: pressure, sample: s)
        } else if !tipNow && tipDown {
            tipDown = false
            setButton(.left, down: false, at: p, pressure: 0, sample: s)
        }

        // Barrel buttons (secondary / middle). Update state BEFORE posting: the
        // posted event reads the button state via currentButtonMask(), so we must
        // not hold an exclusive (inout) access across the call.
        if s.barrel1 != barrel1Down {
            barrel1Down = s.barrel1
            setButton(.right, down: s.barrel1, at: p, pressure: 0, sample: s)
        }
        if s.barrel2 != barrel2Down {
            barrel2Down = s.barrel2
            setButton(.center, down: s.barrel2, at: p, pressure: 0, sample: s)
        }

        // Motion: choose the drag/move type based on what's held.
        let type: CGEventType
        let button: CGMouseButton
        if tipDown            { type = .leftMouseDragged;  button = .left }
        else if barrel1Down   { type = .rightMouseDragged; button = .right }
        else if barrel2Down   { type = .otherMouseDragged; button = .center }
        else                  { type = .mouseMoved;        button = .left }

        postMouse(type: type, button: button, at: p, pressure: tipDown ? pressure : 0, sample: s)
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
        var b: Int64 = 0
        if tipDown { b |= 1 }
        if barrel1Down { b |= 2 }
        if barrel2Down { b |= 4 }
        return b
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
        e.setIntegerValueField(.tabletProximityEventVendorPointerType, value: 0x0802) // Wacom pen
        e.setIntegerValueField(.tabletProximityEventVendorPointerSerialNumber, value: 1)
        e.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: 1)
        e.setIntegerValueField(.tabletProximityEventCapabilityMask, value: capabilityMask)
        e.setIntegerValueField(.tabletProximityEventPointerType, value: 1) // NX_TABLET_POINTER_PEN
        e.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        e.post(tap: .cghidEventTap)
    }
}
