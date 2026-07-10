// AppDelegate.swift — menu-bar item and windows.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var calibration: CalibrationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "WacomTablet")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Calibrate…", action: #selector(runCalibration), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        model.onCalibrate = { [weak self] in self?.runCalibration() }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(model))
            let win = NSWindow(contentViewController: hosting)
            win.title = "WacomTablet Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 480, height: 460))
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func runCalibration() {
        calibration = CalibrationController(model: model)
        calibration?.begin { [weak self] in self?.calibration = nil }
    }

    @objc func quit() {
        model.engine.stop()
        NSApp.terminate(nil)
    }
}
