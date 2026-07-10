// wacom-inject-test — Milestone 0b feasibility spike
//
// Proves that macOS apps read pen pressure from the *public* CGEvent tablet
// fields. Two modes:
//
//   listen : opens a window whose view logs NSEvent pressure/subtype/type.
//   inject : posts a tablet-subtype drag whose pressure ramps 0 -> 1 at the
//            centre of the main screen.
//
// Verify:
//   Terminal A:  swift run wacom-inject-test listen     (click the window to focus it)
//   Terminal B:  swift run wacom-inject-test inject
// Success = the listen window logs mouse/tablet events with pressure climbing
// from ~0 to ~1. (Also try pointing `inject` at Krita/Photoshop.)
//
// `inject` needs Accessibility permission (Privacy & Security ▸ Accessibility).

import AppKit
import CoreGraphics

// MARK: - listen mode

final class LoggingView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func awakeFromNib() { window?.acceptsMouseMovedEvents = true }

    private func log(_ e: NSEvent) {
        // subtype is only meaningful for mouse-type events
        let subtype: String
        switch e.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved:
            subtype = "\(e.subtype.rawValue)"
        default:
            subtype = "-"
        }
        print(String(format: "type=%2ld subtype=%@ pressure=%.3f tiltX=%.2f tiltY=%.2f",
                     e.type.rawValue, subtype, e.pressure,
                     e.type == .tabletPoint ? e.tilt.x : 0,
                     e.type == .tabletPoint ? e.tilt.y : 0))
    }

    override func mouseDown(with e: NSEvent) { log(e) }
    override func mouseDragged(with e: NSEvent) { log(e) }
    override func mouseUp(with e: NSEvent) { log(e) }
    override func mouseMoved(with e: NSEvent) { log(e) }
    override func tabletPoint(with e: NSEvent) { log(e) }
    override func tabletProximity(with e: NSEvent) {
        print("tabletProximity entering=\(e.isEnteringProximity)")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.darkGray.setFill(); dirtyRect.fill()
        ("Focus me, then run `inject` in another terminal" as NSString).draw(
            at: NSPoint(x: 20, y: 20),
            withAttributes: [.foregroundColor: NSColor.white])
    }
}

func runListen() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 240),
                       styleMask: [.titled, .closable],
                       backing: .buffered, defer: false)
    win.title = "wacom-inject-test — pressure logger"
    win.contentView = LoggingView()
    win.acceptsMouseMovedEvents = true
    win.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
    fatalError()
}

// MARK: - inject mode

func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }

func runInject() {
    guard let screen = NSScreen.main else { fatalError("no screen") }
    // CoreGraphics uses a top-left origin; NSScreen is bottom-left. Use the
    // screen centre, which is origin-agnostic.
    let p = CGPoint(x: screen.frame.midX, y: screen.frame.height - screen.frame.midY)
    let deviceID: Int64 = 0x1

    // Proximity-in so the target app switches into tablet mode.
    if let prox = CGEvent(source: nil) {
        prox.type = .mouseMoved
        prox.location = p
        prox.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletProximity.rawValue))
        prox.setIntegerValueField(.tabletProximityEventVendorID, value: 0x056a)
        prox.setIntegerValueField(.tabletProximityEventDeviceID, value: deviceID)
        prox.setIntegerValueField(.tabletProximityEventPointerType, value: 1) // pen
        prox.setIntegerValueField(.tabletProximityEventEnterProximity, value: 1)
        post(prox)
    }
    usleep(50_000)

    // Mouse-down at the point.
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
    down?.setIntegerValueField(.tabletEventDeviceID, value: deviceID)
    down?.setDoubleValueField(.tabletEventPointPressure, value: 0.0)
    post(down)

    // Drag with pressure ramping 0 -> 1.
    for i in 0...40 {
        let pressure = Double(i) / 40.0
        let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
        drag?.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        drag?.setIntegerValueField(.tabletEventDeviceID, value: deviceID)
        drag?.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        drag?.setDoubleValueField(.tabletEventTiltX, value: pressure - 0.5)
        drag?.setDoubleValueField(.tabletEventTiltY, value: 0.5 - pressure)
        post(drag)
        print(String(format: "posted drag pressure=%.3f", pressure))
        usleep(40_000)
    }

    // Mouse-up + proximity-out.
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
    up?.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
    up?.setDoubleValueField(.tabletEventPointPressure, value: 0.0)
    post(up)

    if let prox = CGEvent(source: nil) {
        prox.type = .mouseMoved
        prox.location = p
        prox.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletProximity.rawValue))
        prox.setIntegerValueField(.tabletProximityEventDeviceID, value: deviceID)
        prox.setIntegerValueField(.tabletProximityEventEnterProximity, value: 0)
        post(prox)
    }
    print("done.")
}

// MARK: - main

let mode = CommandLine.arguments.dropFirst().first ?? "help"
switch mode {
case "listen": runListen()
case "inject": runInject()
default:
    print("""
    usage: wacom-inject-test <listen|inject>
      listen   open a window that logs NSEvent pressure/subtype
      inject   post a tablet drag with pressure ramping 0 -> 1 at screen centre
    """)
}
