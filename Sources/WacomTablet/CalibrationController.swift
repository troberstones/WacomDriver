// CalibrationController.swift — full-screen 4-point calibration on the Cintiq.
//
// Shows a target near each corner; the user taps each with the pen. We capture
// the raw tablet coordinates at each tap, pair them with the target's known
// display-local screen point, and solve a raw→local affine transform. Keeping the
// fit display-local (offset-free) lets the calibration survive the Cintiq moving
// in the display arrangement — Calibration.screenPoint re-adds the live origin.

import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

final class CalibrationController {
    private let model: AppModel
    private var window: NSWindow?
    private var view: CalibrationView?
    private var completion: (() -> Void)?

    private var targets: [CGPoint] = []                       // global top-left points
    private var captured: [(raw: CGPoint, screen: CGPoint)] = []
    private var index = 0
    // Require the pen to be lifted before a tap counts — including before the
    // FIRST one, so a pen already touching (or a stale sample) when the window
    // opens can't silently consume target 1 with a garbage coordinate.
    private var armed = false

    init(model: AppModel) { self.model = model }

    func begin(completion: @escaping () -> Void) {
        self.completion = completion
        model.calibration.pickDisplay()
        let b = model.calibration.screenBounds
        let inx = b.width * 0.12, iny = b.height * 0.12
        targets = [
            CGPoint(x: b.minX + inx, y: b.minY + iny),        // TL
            CGPoint(x: b.maxX - inx, y: b.minY + iny),        // TR
            CGPoint(x: b.minX + inx, y: b.maxY - iny),        // BL
            CGPoint(x: b.maxX - inx, y: b.maxY - iny),        // BR
        ]

        let screen = NSScreen.screens.first { $0.displayID == model.calibration.displayID } ?? NSScreen.main!
        let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.backgroundColor = .black
        win.isOpaque = true
        let v = CalibrationView()
        v.target = toView(targets[0])
        v.step = 1
        v.onCancel = { [weak self] in self?.cancel() }
        win.contentView = v
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
        view = v

        model.engine.suppressInjection = true
        model.engine.rawPenHook = { [weak self] s in self?.handle(s) }
    }

    private func handle(_ s: PenSample) {
        let down = s.pressure > 40
        if !down { armed = true; return }
        guard armed else { return }
        armed = false

        // Store the target in DISPLAY-LOCAL coords (subtract the display's global
        // origin) so the solved affine is independent of where the Cintiq sits in
        // the arrangement; Calibration.screenPoint re-adds the live origin.
        let b = model.calibration.screenBounds
        let localTarget = CGPoint(x: targets[index].x - b.minX, y: targets[index].y - b.minY)
        captured.append((raw: CGPoint(x: s.x, y: s.y), screen: localTarget))
        index += 1
        if index >= targets.count {
            finish()
        } else {
            view?.target = toView(targets[index])
            view?.step = index + 1
            view?.needsDisplay = true
        }
    }

    private func finish() {
        let affine = AffineSolver.solve(captured)
        teardown()
        model.setCalibration(affine: affine)
        completion?()
    }

    private func cancel() {
        teardown()          // leave existing calibration untouched
        completion?()
    }

    private func teardown() {
        model.engine.rawPenHook = nil
        model.engine.suppressInjection = false
        window?.orderOut(nil)
        window = nil
    }

    /// Global top-left point → the borderless window's bottom-left view coords.
    private func toView(_ p: CGPoint) -> CGPoint {
        let b = model.calibration.screenBounds
        return CGPoint(x: p.x - b.minX, y: b.height - (p.y - b.minY))
    }
}

final class CalibrationView: NSView {
    var target: CGPoint = .zero
    var step = 1
    var onCancel: (() -> Void)?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        // Target crosshair.
        let r: CGFloat = 22
        let ring = NSBezierPath(ovalIn: NSRect(x: target.x - r, y: target.y - r, width: 2 * r, height: 2 * r))
        NSColor.systemGreen.setStroke()
        ring.lineWidth = 3
        ring.stroke()
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: target.x - r - 8, y: target.y))
        cross.line(to: CGPoint(x: target.x + r + 8, y: target.y))
        cross.move(to: CGPoint(x: target.x, y: target.y - r - 8))
        cross.line(to: CGPoint(x: target.x, y: target.y + r + 8))
        cross.lineWidth = 1.5
        cross.stroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: target.x - 2, y: target.y - 2, width: 4, height: 4))
        NSColor.systemGreen.setFill()
        dot.fill()

        let text = "Calibration \(step) / 4\n\nTap the green target with the pen tip.\n(Esc to cancel)"
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 20),
            .paragraphStyle: style,
        ]
        let size = bounds.size
        let tr = NSRect(x: 0, y: size.height / 2 - 60, width: size.width, height: 120)
        (text as NSString).draw(in: tr, withAttributes: attrs)
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // Esc
    }
}
