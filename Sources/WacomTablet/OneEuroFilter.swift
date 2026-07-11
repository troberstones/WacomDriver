// OneEuroFilter.swift — adaptive low-pass filter for cursor position.
//
// The 1€ filter (Casiez, Roussel, Vogel, CHI 2012) smooths jitter when the pen
// moves slowly (hovering) yet stays responsive when it moves fast, so the
// cursor doesn't lag behind quick motions. Used only while the tip is up — a
// drawing stroke wants the raw, unfiltered points.

import Foundation
import CoreGraphics

private struct LowPass {
    private var value: Double?
    mutating func filter(_ x: Double, alpha: Double) -> Double {
        let out = value.map { alpha * x + (1 - alpha) * $0 } ?? x
        value = out
        return out
    }
    var last: Double? { value }
    mutating func reset() { value = nil }
}

/// One 1€ filter over a scalar. `minCutoff` sets the smoothing floor (lower =
/// smoother when still); `beta` sets how much fast motion loosens it.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double = 1.0

    private var x = LowPass()
    private var dx = LowPass()
    private var lastTime: Double?

    init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    private func alpha(_ cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    mutating func filter(_ value: Double, at time: Double) -> Double {
        defer { lastTime = time }
        guard let prev = lastTime, time > prev else {
            _ = x.filter(value, alpha: 1)      // seed
            return value
        }
        let dt = time - prev
        let dValue = ((x.last.map { value - $0 }) ?? 0) / dt
        let edx = dx.filter(dValue, alpha: alpha(dCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(edx)
        return x.filter(value, alpha: alpha(cutoff, dt: dt))
    }

    mutating func reset() {
        x.reset(); dx.reset(); lastTime = nil
    }
}

/// 2-D convenience wrapper. `amount` in 0…1 maps to filter strength; 0 disables.
struct PointSmoother {
    private var fx: OneEuroFilter
    private var fy: OneEuroFilter
    var amount: Double

    init(amount: Double) {
        self.amount = amount
        // amount 0→light (cutoff 8Hz), 1→heavy (cutoff 0.6Hz). beta keeps fast
        // moves responsive.
        let cutoff = 8.0 - 7.4 * min(max(amount, 0), 1)
        fx = OneEuroFilter(minCutoff: cutoff, beta: 0.02)
        fy = OneEuroFilter(minCutoff: cutoff, beta: 0.02)
    }

    mutating func setAmount(_ a: Double) {
        guard a != amount else { return }
        self = PointSmoother(amount: a)
    }

    mutating func filter(_ p: CGPoint, at t: Double) -> CGPoint {
        guard amount > 0 else { return p }
        return CGPoint(x: fx.filter(Double(p.x), at: t),
                       y: fy.filter(Double(p.y), at: t))
    }

    mutating func reset() { fx.reset(); fy.reset() }
}
