// WacomEngine.swift — shared driver core used by both the headless daemon and
// the GUI app. Owns the HID manager: seizes the DTK-2100, switches it to Wacom
// mode, parses reports, and dispatches to the injector / pad handler.
//
// IOKit C callbacks receive `self` via an opaque context pointer, so there is no
// global state. All callbacks fire on the run loop the engine is started on.

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

final class WacomEngine {
    static let vendorID = 0x056a
    static let productID = 0x00cc
    private let bufferSize = 64

    let calibration: Calibration
    private let injector: EventInjector
    private let padHandler: PadHandler

    var debug = false
    /// When true, pen samples are parsed but not injected (identify / calibration).
    var suppressInjection = false
    /// Fires on every raw pen sample — used by the calibration UI to capture
    /// tablet coordinates at each corner target.
    var rawPenHook: ((PenSample) -> Void)?
    /// Fires when the tablet is seized and live.
    var onReady: (() -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let reportBuffer: UnsafeMutablePointer<UInt8>

    init(calibration: Calibration, injector: EventInjector, padHandler: PadHandler) {
        self.calibration = calibration
        self.injector = injector
        self.padHandler = padHandler
        self.reportBuffer = .allocate(capacity: bufferSize)
    }

    func start(on runLoop: CFRunLoop = CFRunLoopGetCurrent()) {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
        ]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, device in
            Unmanaged<WacomEngine>.fromOpaque(ctx!).takeUnretainedValue().deviceMatched(device)
        }, ctx)
        // Hot-plug: on unplug, drop the stale handle so a replug re-seizes cleanly.
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, device in
            Unmanaged<WacomEngine>.fromOpaque(ctx!).takeUnretainedValue().deviceRemoved(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, runLoop, CFRunLoopMode.defaultMode.rawValue)
        let status = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if status != kIOReturnSuccess {
            print(String(format: "IOHIDManagerOpen failed (0x%08x) — grant Input Monitoring / try sudo.", status))
        }
    }

    func stop() {
        injector.leaveProximity()
        if let d = device { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) }
        device = nil
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard status == kIOReturnSuccess else {
            print(String(format: "seize failed (0x%08x). Grant Input Monitoring / try sudo.", status))
            return
        }
        self.device = device
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, bufferSize, { ctx, result, _, _, _, report, len in
            guard result == kIOReturnSuccess else { return }
            Unmanaged<WacomEngine>.fromOpaque(ctx!).takeUnretainedValue().handleReport(report, Int(len))
        }, ctx)
        switchToWacomMode(device)
        onReady?()
    }

    private func deviceRemoved(_ removed: IOHIDDevice) {
        guard removed == device else { return }
        injector.leaveProximity()   // release any held buttons / proximity
        device = nil
        if debug { print("DTK-2100 unplugged; waiting for replug…") }
    }

    private func switchToWacomMode(_ device: IOHIDDevice) {
        let payload: [UInt8] = [0x02, 0x02]
        let status = payload.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 2, $0.baseAddress!, $0.count)
        }
        if status != kIOReturnSuccess {
            print(String(format: "warning: mode-switch feature report failed (0x%08x)", status))
        }
    }

    private func handleReport(_ report: UnsafeMutablePointer<UInt8>, _ len: Int) {
        guard len >= 10 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: len))
        switch WacomProtocol.parse(bytes) {
        case .penData(let s):
            if debug { print("pen x=\(s.x) y=\(s.y) p=\(s.pressure) tilt=(\(s.tiltX),\(s.tiltY)) b1=\(s.barrel1) b2=\(s.barrel2)") }
            rawPenHook?(s)
            if !suppressInjection { injector.handle(s) }
        case .proximityIn(let tool):
            if debug { print("proximity in: tool=\(tool)") }
            if !suppressInjection { injector.enterProximity(tool: tool) }
        case .proximityOut:
            if !suppressInjection { injector.leaveProximity() }
        case .pad(let pad):
            if debug { print("pad L=0x\(String(pad.leftKeys, radix: 16)) R=0x\(String(pad.rightKeys, radix: 16)) LT=\(pad.leftToggle) RT=\(pad.rightToggle) lStrip=\(pad.leftStrip) rStrip=\(pad.rightStrip)") }
            padHandler.handle(pad)
        case .other:
            break
        }
    }
}
