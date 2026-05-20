// DiagnosticRedactor.swift — ZoomNukeCore
//
// CANONICAL SOURCE for DiagnosticRedactor.
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

// MARK: - DiagnosticRedactor

/// Removes or masks sensitive data from log text before it leaves the device.
///
/// What is redacted:
/// - Absolute home-directory paths  → `~/…`
/// - Email addresses                → `[email]`
/// - IPv4 / IPv6 addresses          → `[ip]`
/// - macOS Hardware UUID / serial   → `[redacted]`
/// - Common secret env-var values   → `[redacted]`
///
/// What is NOT redacted (intentionally kept for support usefulness):
/// - macOS version, architecture
/// - Application paths outside ~
/// - Exit codes, command names, step names
/// - Timestamps
struct DiagnosticRedactor {

    // MARK: - Privacy warning

    /// Show this text to the user before any copy / export / send action.
    static let privacyWarning = """
    This report may contain local file paths, hardware information, \
    macOS version details, and command output from your system. \
    Review the content before sending it to anyone.
    """

    // MARK: - Redaction

    /// Returns a copy of `text` with sensitive data replaced.
    static func redact(_ text: String) -> String {
        var result = text

        // 1. Replace /Users/<name>/… with ~/…
        result = redactHomePaths(result)

        // 2. Email addresses
        result = applyRegex(result,
                            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
                            replacement: "[email]")

        // 3. IPv4 addresses (avoid over-matching version strings like "12.6.1")
        result = applyRegex(result,
                            pattern: #"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"#,
                            replacement: "[ip]")

        // 4. IPv6 addresses (simplified heuristic)
        result = applyRegex(result,
                            pattern: #"\b(?:[0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}\b"#,
                            replacement: "[ip]")

        // 5. macOS Hardware UUID (8-4-4-4-12 uppercase hex)
        result = applyRegex(result,
                            pattern: #"\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b"#,
                            replacement: "[uuid]")

        // 6. Serial numbers (e.g. "Serial Number: XYZABC123456")
        result = applyRegex(result,
                            pattern: #"(?i)serial\s+number\s*:?\s+[A-Z0-9]{8,}"#,
                            replacement: "Serial Number: [redacted]")

        // 7. Common secret env-var values in log lines like KEY=value or KEY="value"
        //    Only matches known sensitive key names to avoid over-redaction.
        let secretKeys = ["PASSWORD", "TOKEN", "SECRET", "API_KEY", "COOKIE", "SESSION",
                          "CREDENTIAL", "PRIVATE_KEY", "ACCESS_KEY"]
        for key in secretKeys {
            result = applyRegex(result,
                                pattern: "(?i)\(key)\\s*=\\s*[^\\s]+",
                                replacement: "\(key)=[redacted]")
        }

        return result
    }

    // MARK: - Private helpers

    private static func redactHomePaths(_ text: String) -> String {
        // Match /Users/<any-username>/ and replace with ~/
        // The username is one or more path-safe characters (no / or NUL).
        return applyRegex(text,
                          pattern: #"/Users/[^/\s]+"#,
                          replacement: "~")
    }

    private static func applyRegex(_ text: String,
                                    pattern: String,
                                    replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range,
                                               withTemplate: replacement)
    }
}
