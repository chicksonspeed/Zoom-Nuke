// swift-tools-version: 5.9
// Package.swift — used for IDE support (Xcode, VS Code) and CI compilation checks.
//
// To build the distributable .app bundle, use tools/build_macos_app.sh instead:
//   ./tools/build_macos_app.sh
//
// SPM produces a command-line executable; the build_macos_app.sh script wraps it
// in a proper .app bundle with Info.plist, icons, and bundled shell scripts.

import PackageDescription

let package = Package(
    name: "ZoomNuke",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ZoomNuke",
            path: "app",
            exclude: ["ZoomNuke.icns"]
        )
    ]
)
