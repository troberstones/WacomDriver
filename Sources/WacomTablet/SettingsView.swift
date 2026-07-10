// SettingsView.swift — the settings window: button mapping, pressure, calibration.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            ButtonsTab().tabItem { Text("Buttons") }
            PressureTab().tabItem { Text("Pressure") }
            CalibrationTab().tabItem { Text("Calibration") }
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - Buttons

private struct ButtonsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("ExpressKeys & Toggles").font(.headline)
                Text("Type a shortcut: e.g.  cmd+z   ·   hold shift   ·   b")
                    .font(.caption).foregroundColor(.secondary)

                ForEach(PadConfig.buttonIDs, id: \.self) { id in
                    HStack {
                        Text(id)
                            .frame(width: 32, alignment: .leading)
                            .font(.system(.body, design: .monospaced))
                        TextField("(unset)", text: binding(for: id))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Divider().padding(.vertical, 4)
                Text("Touch Strips").font(.headline)
                stripRow("Left strip", keyPath: \.leftStrip)
                stripRow("Right strip", keyPath: \.rightStrip)
            }
            .padding()
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { model.padConfig.buttons[id]?.display ?? "" },
            set: { text in
                model.padConfig.buttons[id] = KeyAction.parse(text)
                model.applyPad()
            })
    }

    @ViewBuilder
    private func stripRow(_ label: String, keyPath: WritableKeyPath<PadConfig, StripAction>) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            Picker("", selection: Binding(
                get: { StripPreset.from(model.padConfig[keyPath: keyPath]) },
                set: { preset in
                    model.padConfig[keyPath: keyPath] = preset.action
                    model.applyPad()
                })) {
                    ForEach(StripPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
        }
    }
}

private enum StripPreset: String, CaseIterable, Identifiable {
    case scroll = "Scroll", zoom = "Zoom", brush = "Brush size"
    var id: String { rawValue }

    var action: StripAction {
        switch self {
        case .scroll: return StripAction(mode: "scroll", up: nil, down: nil)
        case .zoom:   return StripAction(mode: "keys",
                                         up: KeyAction(type: "chord", mods: ["cmd"], key: "=", label: nil),
                                         down: KeyAction(type: "chord", mods: ["cmd"], key: "-", label: nil))
        case .brush:  return StripAction(mode: "keys",
                                         up: KeyAction(type: "chord", mods: [], key: "]", label: nil),
                                         down: KeyAction(type: "chord", mods: [], key: "[", label: nil))
        }
    }

    static func from(_ s: StripAction) -> StripPreset {
        if s.mode == "scroll" { return .scroll }
        if s.up?.key == "=" { return .zoom }
        return .brush
    }
}

// MARK: - Pressure

private struct PressureTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pressure curve").font(.headline)
            CurvePreview(curve: model.penConfig.pressure)
                .frame(height: 170)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))

            HStack {
                Text("Soft")
                Slider(value: Binding(
                    get: { model.penConfig.pressureGamma },
                    set: { g in
                        model.penConfig.pressureGamma = g
                        model.penConfig.pressure = .gamma(g)
                        model.applyPen()
                    }), in: 0.4...2.5)
                Text("Firm")
            }
            Text(String(format: "gamma %.2f  (1.0 = linear)", model.penConfig.pressureGamma))
                .font(.caption).foregroundColor(.secondary)

            Button("Reset to linear") {
                model.penConfig.pressureGamma = 1.0
                model.penConfig.pressure = .linear
                model.applyPen()
            }
            Spacer()
        }
        .padding()
    }
}

private struct CurvePreview: View {
    let curve: PressureCurve
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let n = 48
            for i in 0...n {
                let x = Double(i) / Double(n)
                let y = curve.apply(x)
                let pt = CGPoint(x: x * size.width, y: size.height * (1 - y))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
    }
}

// MARK: - Calibration

private struct CalibrationTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Screen calibration").font(.headline)
            Text("Aligns the pen tip with the cursor on the Cintiq. You tap four targets, one near each corner.")
                .font(.caption).foregroundColor(.secondary)

            Text(model.penConfig.affine == nil ? "Status: uncalibrated (linear map)" : "Status: calibrated ✓")
                .foregroundColor(model.penConfig.affine == nil ? .secondary : .green)

            Button("Run Calibration…") { model.onCalibrate?() }

            if model.penConfig.affine != nil {
                Button("Clear calibration") { model.setCalibration(affine: nil) }
            }

            Divider()
            Text("Display \(model.calibration.displayID): \(Int(model.calibration.screenBounds.width))×\(Int(model.calibration.screenBounds.height))")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
