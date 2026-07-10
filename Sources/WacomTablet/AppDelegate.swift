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
        model.onCalibrate = { [weak self] in self?.runCalibration() }
        model.onProfilesChanged = { [weak self] in self?.rebuildMenu() }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Profiles submenu.
        let profilesItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profilesMenu = NSMenu()
        for p in model.store.profiles {
            let item = NSMenuItem(title: p.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.name
            item.state = (p.name == model.store.activeName) ? .on : .off
            profilesMenu.addItem(item)
        }
        profilesMenu.addItem(.separator())
        let newItem = NSMenuItem(title: "New Profile", action: #selector(newProfile), keyEquivalent: "")
        newItem.target = self
        profilesMenu.addItem(newItem)
        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Calibrate…", action: #selector(runCalibration), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        statusItem.menu = menu
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { model.switchProfile(name) }
    }

    @objc private func newProfile() {
        model.addProfile()
        openSettings()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(model))
            let win = NSWindow(contentViewController: hosting)
            win.title = "WacomTablet Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 500, height: 480))
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
