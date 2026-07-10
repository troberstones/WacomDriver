// main.swift — entry point. `--headless` runs the daemon; otherwise the
// menu-bar GUI app.

import AppKit

if CommandLine.arguments.contains("--headless") {
    runHeadless()
}

if CommandLine.arguments.contains("--dump-config") {
    print(PadConfig.defaults.jsonString())
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar app, no Dock icon
app.run()
