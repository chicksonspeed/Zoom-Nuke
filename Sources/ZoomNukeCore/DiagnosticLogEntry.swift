// DiagnosticLogEntry.swift — ZoomNukeCore
//
// CANONICAL SOURCE for DiagnosticLogEntry and LogLevel.
//
// This file lives in Sources/ZoomNukeCore/ and is compiled in two contexts:
//   1. As part of the ZoomNukeCore library  → used by ZoomNukeTests (XCTest).
//   2. Directly included in the ZoomNuke executable's sources list in
//      Package.swift → visible to all app/ files in the same module without
//      needing `import ZoomNukeCore`.
//   3. tools/build_macos_app.sh globs Sources/ZoomNukeCore/*.swift alongside
//      app/*.swift in a single swiftc call.
//
// Do NOT create a copy of this file in app/.  If you need to add a new type
// that belongs in this module, add it here and update Package.swift sources.

import Foundation

// MARK: - Log Level

/// Severity levels used by both the Swift app and the shell logging library.
/// Raw values must stay in sync with `_shared_logging.sh`.
enum LogLevel: String, CaseIterable {
    case info    = "INFO"
    case step    = "STEP"
    case success = "SUCCESS"
    case warning = "WARNING"
    case error   = "ERROR"
    case debug   = "DEBUG"
}

// MARK: - DiagnosticLogEntry

/// One structured log record.
/// All fields are value types — safe to copy across threads.
struct DiagnosticLogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let subsystem: String
    let message: String

    // Optional contextual fields — only populated when relevant.
    let command: String?
    let path: String?
    let exitCode: Int?
    let duration: TimeInterval?
    let suggestedFix: String?

    init(
        level: LogLevel,
        subsystem: String,
        message: String,
        command: String?        = nil,
        path: String?           = nil,
        exitCode: Int?          = nil,
        duration: TimeInterval? = nil,
        suggestedFix: String?   = nil
    ) {
        self.id           = UUID()
        self.timestamp    = Date()
        self.level        = level
        self.subsystem    = subsystem
        self.message      = message
        self.command      = command
        self.path         = path
        self.exitCode     = exitCode
        self.duration     = duration
        self.suggestedFix = suggestedFix
    }

    // MARK: - Formatting

    /// Single-line representation written to disk and readable in a text editor.
    func formatted() -> String {
        let ts   = DiagnosticLogEntry.timestampFormatter.string(from: timestamp)
        var line = "[\(ts)] [\(level.rawValue)] [\(subsystem)] \(message)"
        if let cmd  = command      { line += " | cmd=\(cmd)" }
        if let p    = path         { line += " | path=\(p)" }
        if let code = exitCode     { line += " | exit=\(code)" }
        if let d    = duration     { line += String(format: " | duration=%.2fs", d) }
        if let fix  = suggestedFix { line += "\n   fix: \(fix)" }
        return line
    }

    // MARK: - Private

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
