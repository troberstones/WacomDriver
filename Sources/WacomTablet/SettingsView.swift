// SettingsView.swift — settings window: profiles, button mapping, pen buttons,
// pressure, calibration. All edits target the active profile (except
// calibration, which is global).

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Editing profile:").foregroundColor(.secondary)
                Text(model.store.activeName).bold()
                Spacer()
            }
            .padding(.horizontal).padding(.top, 8)

            TabView {
                ProfilesTab().tabItem { Text("Profiles") }
                ButtonsTab().tabItem { Text("Buttons") }
                PenTab().tabItem { Text("Pen") }
                PressureTab().tabItem { Text("Pressure") }
                CalibrationTab().tabItem { Text("Calibration") }
            }
            .padding(8)
        }
        .frame(width: 500, height: 480)
    }
}

// MARK: - Profiles

private struct ProfilesTab: View {
    @EnvironmentObject var model: AppModel
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Profiles").font(.headline)
            Text("Each profile is a full set of button, pen, and pressure settings — e.g. one per app. Switch the active one here or from the menu bar.")
                .font(.caption).foregroundColor(.secondary)

            Picker("Active", selection: Binding(
                get: { model.store.activeName },
                set: { model.switchProfile($0) })) {
                    ForEach(model.store.profiles) { Text($0.name).tag($0.name) }
                }

            HStack {
                Button("New (clone current)") { model.addProfile() }
                Button("Delete") { model.deleteProfile(model.store.activeName) }
                    .disabled(model.store.profiles.count <= 1)
            }

            Divider()
            Text("Rename active profile").font(.subheadline)
            HStack {
                TextField(model.store.activeName, text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Rename") {
                    model.renameActive(newName)
                    newName = ""
                }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                        Text(id).frame(width: 32, alignment: .leading)
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
            get: { model.activeProfile.pad.buttons[id]?.display ?? "" },
            set: { text in model.updateActive { $0.pad.buttons[id] = KeyAction.parse(text) } })
    }

    @ViewBuilder
    private func stripRow(_ label: String, keyPath: WritableKeyPath<PadConfig, StripAction>) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            Picker("", selection: Binding(
                get: { StripPreset.from(model.activeProfile.pad[keyPath: keyPath]) },
                set: { preset in model.updateActive { $0.pad[keyPath: keyPath] = preset.action } })) {
                    ForEach(StripPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented)
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

// MARK: - Pen buttons

private struct PenTab: View {
    @EnvironmentObject var model: AppModel
    private let choices = ["left", "right", "middle", "none"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pen buttons").font(.headline)
            Text("Assign the pen tip and the two barrel buttons to mouse clicks.")
                .font(.caption).foregroundColor(.secondary)

            row("Tip", get: { model.activeProfile.penButtons.tip },
                set: { v in model.updateActive { $0.penButtons.tip = v } })
            row("Lower barrel", get: { model.activeProfile.penButtons.barrel1 },
                set: { v in model.updateActive { $0.penButtons.barrel1 = v } })
            row("Upper barrel", get: { model.activeProfile.penButtons.barrel2 },
                set: { v in model.updateActive { $0.penButtons.barrel2 = v } })
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func row(_ label: String, get: @escaping () -> String, set: @escaping (String) -> Void) -> some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            Picker("", selection: Binding(get: get, set: set)) {
                Text("Left click").tag("left")
                Text("Right click").tag("right")
                Text("Middle click").tag("middle")
                Text("None").tag("none")
            }
            .labelsHidden().pickerStyle(.segmented)
        }
    }
}

// MARK: - Pressure

private struct PressureTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pressure curve").font(.headline)
            CurvePreview(curve: model.activeProfile.pressure)
                .frame(height: 170)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))

            HStack {
                Text("Soft")
                Slider(value: Binding(
                    get: { model.activeProfile.pressureGamma },
                    set: { g in model.updateActive { $0.pressureGamma = g; $0.pressure = .gamma(g) } }),
                       in: 0.4...2.5)
                Text("Firm")
            }
            Text(String(format: "gamma %.2f  (1.0 = linear)", model.activeProfile.pressureGamma))
                .font(.caption).foregroundColor(.secondary)

            Button("Reset to linear") {
                model.updateActive { $0.pressureGamma = 1.0; $0.pressure = .linear }
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
                let pt = CGPoint(x: x * size.width, y: size.height * (1 - curve.apply(x)))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
    }
}

// MARK: - Calibration (global)

private struct CalibrationTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Screen calibration").font(.headline)
            Text("Global (shared by all profiles). Aligns the pen tip with the cursor on the Cintiq. You tap four targets, one near each corner.")
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
