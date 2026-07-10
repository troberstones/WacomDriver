// PenSettings.swift — persisted pen mapping settings: display target, optional
// 4-point affine calibration, and a pressure curve. Loaded from
// ~/.config/wacomd/pen.json (or WACOM_PEN_CONFIG); written by the GUI.

import Foundation
import CoreGraphics

// A pressure response curve as sorted control points in the unit square.
struct PressureCurve: Codable, Equatable {
    var points: [[Double]]   // [[x,y], …] with x in 0…1, sorted

    static let linear = PressureCurve(points: [[0, 0], [1, 1]])

    /// Map a raw normalized pressure (0…1) through the curve.
    func apply(_ p: Double) -> Double {
        let x = min(max(p, 0), 1)
        let pts = points.sorted { $0[0] < $1[0] }
        guard pts.count >= 2 else { return x }
        if x <= pts[0][0] { return clamp(pts[0][1]) }
        for i in 1..<pts.count where x <= pts[i][0] {
            let (x0, y0) = (pts[i - 1][0], pts[i - 1][1])
            let (x1, y1) = (pts[i][0], pts[i][1])
            let t = (x - x0) / max(x1 - x0, 1e-9)
            return clamp(y0 + t * (y1 - y0))
        }
        return clamp(pts.last![1])
    }

    /// Convenience: a gamma curve sampled into control points (gamma<1 = softer).
    static func gamma(_ g: Double, samples: Int = 9) -> PressureCurve {
        let pts = (0...samples).map { i -> [Double] in
            let x = Double(i) / Double(samples)
            return [x, pow(x, g)]
        }
        return PressureCurve(points: pts)
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

struct PenConfig: Codable {
    var invertX = false
    var invertY = false
    var displayIndex: Int? = nil
    // raw→screen affine [ax, bx, cx, ay, by, cy]; nil = uncalibrated linear map.
    var affine: [Double]? = nil
    var tabletMaxX = 87200.0
    var tabletMaxY = 65600.0

    static func path() -> String {
        if let p = ProcessInfo.processInfo.environment["WACOM_PEN_CONFIG"] { return p }
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "."
        return "\(home)/.config/wacomd/pen.json"
    }

    static func load() -> PenConfig {
        guard let data = FileManager.default.contents(atPath: path()),
              let cfg = try? JSONDecoder().decode(PenConfig.self, from: data)
        else { return PenConfig() }
        return cfg
    }

    func save() {
        let dir = (PenConfig.path() as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: URL(fileURLWithPath: PenConfig.path()))
        }
    }
}

// Least-squares affine fit of raw tablet points to screen points (needs ≥ 3
// non-collinear correspondences). Returns [ax, bx, cx, ay, by, cy] or nil.
enum AffineSolver {
    static func solve(_ pairs: [(raw: CGPoint, screen: CGPoint)]) -> [Double]? {
        guard pairs.count >= 3 else { return nil }
        // Normal equations: M = Σ vvᵀ (3×3), rhs_x = Σ v·sx, rhs_y = Σ v·sy,
        // where v = [rawX, rawY, 1].
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        var bx = [0.0, 0, 0], by = [0.0, 0, 0]
        for p in pairs {
            let v = [Double(p.raw.x), Double(p.raw.y), 1]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += v[i] * v[j] }
                bx[i] += v[i] * Double(p.screen.x)
                by[i] += v[i] * Double(p.screen.y)
            }
        }
        guard let inv = invert3x3(m) else { return nil }
        let px = mul3(inv, bx)
        let py = mul3(inv, by)
        return [px[0], px[1], px[2], py[0], py[1], py[2]]
    }

    private static func mul3(_ a: [[Double]], _ v: [Double]) -> [Double] {
        (0..<3).map { i in a[i][0] * v[0] + a[i][1] * v[1] + a[i][2] * v[2] }
    }

    private static func invert3x3(_ m: [[Double]]) -> [[Double]]? {
        let a = m[0][0], b = m[0][1], c = m[0][2]
        let d = m[1][0], e = m[1][1], f = m[1][2]
        let g = m[2][0], h = m[2][1], i = m[2][2]
        let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
        let det = a * A + b * B + c * C
        guard abs(det) > 1e-9 else { return nil }
        let id = 1.0 / det
        return [
            [A * id, (c * h - b * i) * id, (b * f - c * e) * id],
            [B * id, (a * i - c * g) * id, (c * d - a * f) * id],
            [C * id, (b * g - a * h) * id, (a * e - b * d) * id],
        ]
    }
}
