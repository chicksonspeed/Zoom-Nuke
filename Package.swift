// swift-tools-version: 5.9
// Package.swift — used for IDE support (Xcode, VS Code) and CI compilation checks.
//
// To build the distributable .app bundle, use tools/build_macos_app.sh instead:
//   ./tools/build_macos_app.sh
//
// SPM produces a command-line executable; the build_macos_app.sh script wraps it
// in a proper .app bundle with Info.plist, icons, and bundled shell scripts.
//
// Source layout
// ─────────────
// Sources/ZoomNukeCore/   — Pure-Foundation types (DiagnosticLogEntry, DiagnosticRedactor).
//                           This is the single canonical location for those files.
//                           - Compiled as a standalone library for `swift test` isolation.
//                           - Also included directly in the ZoomNuke executable sources
//                             so the whole app compiles as one module (no imports needed).
//
// app/                    — SwiftUI / AppKit app layer.  Sees ZoomNukeCore types because
//                           build_macos_app.sh and the SPM sources list include both dirs
//                           in a single swiftc invocation / module.
//
// tests/swift/            — XCTest suite.  Uses `@testable import ZoomNukeCore`.
//
// Run tests:
//   swift test                       # all tests
//   swift test --filter DiagnosticLogEntryTests
//   swift test --filter DiagnosticRedactorTests

import PackageDescription

let package = Package(
    name: "ZoomNuke",
    platforms: [
        .macOS(.v12)
    ],
    targets: [

        // MARK: - App executable
        //
        // path "." + explicit sources lets us compile both app/ and
        // Sources/ZoomNukeCore/ files as a single Swift module so that
        // DiagnosticLogEntry and DiagnosticRedactor are visible to all
        // app/ files without any `import ZoomNukeCore` statement.
        //
        // If you add a new Swift source file to either app/ or
        // Sources/ZoomNukeCore/, add it to this list.
        .executableTarget(
            name: "ZoomNuke",
            path: ".",
            sources: [
                // App layer
                "app/AppDelegate.swift",
                "app/CleanupProcessManager.swift",
                "app/ContentView+Actions.swift",
                "app/ContentView.swift",
                "app/DiagnosticLogger.swift",
                "app/DiagnosticReport.swift",
                "app/ModeRow.swift",
                "app/Models.swift",
                "app/ZoomNukeApp.swift",
                // Core library — single source of truth, compiled here too
                "Sources/ZoomNukeCore/DiagnosticLogEntry.swift",
                "Sources/ZoomNukeCore/DiagnosticRedactor.swift",
            ]
        ),

        // MARK: - Testable library (pure Foundation — no AppKit / SwiftUI)
        //
        // ZoomNukeCore is the single source of truth for DiagnosticLogEntry
        // and DiagnosticRedactor.  The ZoomNuke executable also compiles these
        // files directly (listed in its sources above), so no `import` is
        // needed in app/ files — both dirs build as one module there.
        //
        // ZoomNukeTests imports ZoomNukeCore as an isolated library, keeping
        // tests free of AppKit/SwiftUI dependencies.
        .target(
            name: "ZoomNukeCore",
            path: "Sources/ZoomNukeCore"
        ),

        // MARK: - XCTest suite
        .testTarget(
            name: "ZoomNukeTests",
            dependencies: ["ZoomNukeCore"],
            path: "tests/swift"
        ),
    ]
)
