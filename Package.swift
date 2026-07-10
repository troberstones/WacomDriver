// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "chWacomDriver",
    platforms: [.macOS(.v13)],
    targets: [
        // Milestone 0a: seize the tablet, switch it to Wacom mode, hex-dump raw reports.
        .executableTarget(
            name: "wacom-dump",
            path: "Sources/wacom-dump",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Milestone 0b: post a tablet-subtype drag with rising pressure to prove CGEvent works.
        .executableTarget(
            name: "wacom-inject-test",
            path: "Sources/wacom-inject-test",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Milestone 1: the real pen daemon — seize, parse, map, inject.
        .executableTarget(
            name: "wacomd",
            path: "Sources/wacomd",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
