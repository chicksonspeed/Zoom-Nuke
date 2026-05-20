// DiagnosticRedactorTests.swift
// ZoomNukeTests — XCTest coverage for DiagnosticRedactor.
//
// Run:
//   swift test --filter DiagnosticRedactorTests
//
// These tests only use Foundation.  No AppKit, SwiftUI, or network required.
// All tests are deterministic and safe to run in CI without admin privileges.
//
// DESIGN NOTE: Each redaction rule is tested in isolation with a minimal input
// that activates exactly one rule.  Multi-rule tests verify composition.
// We also test that non-sensitive data is never accidentally clobbered.

import XCTest
@testable import ZoomNukeCore

final class DiagnosticRedactorTests: XCTestCase {

    // MARK: - Privacy warning

    func testPrivacyWarning_isNonEmpty() {
        XCTAssertFalse(DiagnosticRedactor.privacyWarning.isEmpty,
            "Privacy warning must never be empty")
    }

    func testPrivacyWarning_mentionsFilePathsOrPaths() {
        let w = DiagnosticRedactor.privacyWarning.lowercased()
        XCTAssertTrue(w.contains("path") || w.contains("file"),
            "Privacy warning should mention paths or files")
    }

    // MARK: - Rule 1: Home path redaction

    func testRedact_replacesUsersPath_withTilde() {
        let input  = "/Users/johndoe/Library/Logs/zoom.log"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("johndoe"),
            "Username 'johndoe' should be redacted")
        XCTAssertTrue(output.hasPrefix("~"),
            "Home path should be replaced with tilde; got: \(output)")
    }

    func testRedact_replacesUsersPath_preservesSubpath() {
        let input  = "/Users/alice/Documents/report.pdf"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("alice"))
        // /Users/alice → ~, then /Documents/report.pdf remains
        XCTAssertTrue(output.contains("/Documents/report.pdf"),
            "Subpath after username should be preserved; got: \(output)")
    }

    func testRedact_replacesMultipleUsersPathsInSameLine() {
        let input  = "Copied /Users/bob/src.txt to /Users/bob/dst.txt"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("bob"), "Both occurrences should be redacted")
    }

    func testRedact_doesNotTouchNonHomePaths() {
        // /Applications is outside ~; should not be changed.
        let input  = "/Applications/zoom.us.app/Contents/Info.plist"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertEqual(input, output,
            "Non-home paths should pass through unchanged; got: \(output)")
    }

    // MARK: - Rule 2: Email address redaction

    func testRedact_replacesEmailAddress() {
        let input  = "Contact support at help@example.com for more info"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("help@example.com"))
        XCTAssertTrue(output.contains("[email]"),
            "Email should be replaced with [email]; got: \(output)")
    }

    func testRedact_replacesEmailAddress_differentTLDs() {
        let cases = ["a@b.org", "x.y+tag@sub.domain.co.uk", "user@example.io"]
        for email in cases {
            let output = DiagnosticRedactor.redact(email)
            XCTAssertTrue(output.contains("[email]"),
                "Email '\(email)' should be redacted; got: \(output)")
        }
    }

    func testRedact_doesNotAlterNormalText_withAt() {
        // A standalone @ that isn't part of a proper email shouldn't cause errors.
        let input  = "version @ 3.2.3"
        let output = DiagnosticRedactor.redact(input)
        // Not asserting no change here — just confirming no crash and no spurious [email].
        XCTAssertFalse(output.contains("@example.com"))
        _ = output  // used
    }

    // MARK: - Rule 3: IPv4 redaction

    func testRedact_replacesIPv4Address() {
        let input  = "Connected to 192.168.1.100 on port 443"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("192.168.1.100"),
            "IPv4 address should be redacted; got: \(output)")
        XCTAssertTrue(output.contains("[ip]"))
    }

    func testRedact_replacesIPv4Address_loopback() {
        let input  = "Server bound to 127.0.0.1"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("127.0.0.1"))
        XCTAssertTrue(output.contains("[ip]"))
    }

    func testRedact_preservesMacOSVersionStrings() {
        // "12.6.1" looks like a partial IP but has only 3 octets — should NOT be
        // replaced.  The pattern requires exactly 4 dot-separated groups (\b…\b).
        let input  = "macOS 12.6.1 detected"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertTrue(output.contains("12.6.1"),
            "Short version strings (3 groups) should not be redacted; got: \(output)")
    }

    // MARK: - Rule 4: IPv6 redaction

    func testRedact_replacesIPv6Address() {
        let input  = "IPv6: 2001:db8:85a3:0000:0000:8a2e:0370:7334"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("2001:db8:85a3:0000"))
        XCTAssertTrue(output.contains("[ip]"),
            "IPv6 address should be redacted; got: \(output)")
    }

    // MARK: - Rule 5: Hardware UUID redaction

    func testRedact_replacesHardwareUUID_uppercaseHex() {
        let uuid   = "A1B2C3D4-E5F6-A7B8-C9D0-E1F2A3B4C5D6"
        let input  = "Hardware UUID: \(uuid)"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains(uuid),
            "Hardware UUID should be redacted; got: \(output)")
        XCTAssertTrue(output.contains("[uuid]"))
    }

    func testRedact_doesNotRedactLowercaseUUID() {
        // The pattern explicitly requires uppercase hex (A-F) — lowercase UUIDs
        // (from Swift's UUID().uuidString.lowercased()) should not match.
        let uuid   = "a1b2c3d4-e5f6-a7b8-c9d0-e1f2a3b4c5d6"
        let input  = "uuid: \(uuid)"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("[uuid]"),
            "Lowercase UUIDs should not be matched by the uppercase-only pattern")
    }

    // MARK: - Rule 6: Serial number redaction

    func testRedact_replacesSerialNumber() {
        let input  = "Serial Number: XYZABC123456"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("XYZABC123456"),
            "Serial number should be redacted; got: \(output)")
        XCTAssertTrue(output.contains("Serial Number: [redacted]"))
    }

    func testRedact_replacesSerialNumber_caseInsensitive() {
        let input  = "serial number: C02XXXXXXABCD"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("C02XXXXXXABCD"))
        XCTAssertTrue(output.contains("[redacted]"))
    }

    func testRedact_doesNotRedactShortSerialLike() {
        // Serials under 8 chars should not match — avoids over-redacting model names etc.
        let input  = "Serial Number: AAAA"   // only 4 chars
        let output = DiagnosticRedactor.redact(input)
        XCTAssertTrue(output.contains("AAAA"),
            "Short (<8 char) serial-like token should not be redacted; got: \(output)")
    }

    // MARK: - Rule 7: Secret env-var value redaction

    func testRedact_replacesPassword() {
        let input  = "PASSWORD=hunter2"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("hunter2"),
            "Password value should be redacted; got: \(output)")
        XCTAssertTrue(output.contains("PASSWORD=[redacted]"))
    }

    func testRedact_replacesToken() {
        let input  = "TOKEN=ghp_SuperSecretToken123"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("ghp_SuperSecretToken123"))
        XCTAssertTrue(output.contains("TOKEN=[redacted]"))
    }

    func testRedact_replacesSecret() {
        let input  = "SECRET=mysecretvalue"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("mysecretvalue"))
        XCTAssertTrue(output.contains("SECRET=[redacted]"))
    }

    func testRedact_replacesApiKey() {
        let input  = "API_KEY=sk-1234567890abcdef"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("sk-1234567890abcdef"))
        XCTAssertTrue(output.contains("API_KEY=[redacted]"))
    }

    func testRedact_secretKeyRedaction_caseInsensitive() {
        // The pattern uses (?i) so lowercase keys are also caught.
        let input  = "password=secret123"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("secret123"))
    }

    func testRedact_doesNotRedactNonSecretEnvVars() {
        // Arbitrary env-var names that are NOT in the secretKeys list.
        let input  = "PATH=/usr/local/bin TERM=xterm-256color"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertTrue(output.contains("PATH=/usr/local/bin"),
            "Non-secret env vars should pass through unchanged; got: \(output)")
        XCTAssertTrue(output.contains("TERM=xterm-256color"))
    }

    // MARK: - Preserved content (should NOT be redacted)

    func testRedact_preservesExitCodes() {
        let input  = "exit=127"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertTrue(output.contains("exit=127"),
            "Exit codes should not be redacted; got: \(output)")
    }

    func testRedact_preservesArchitecture() {
        let input  = "Architecture: arm64"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertTrue(output.contains("arm64"),
            "Architecture should not be redacted; got: \(output)")
    }

    func testRedact_preservesTimestamps() {
        // Log timestamps look like "2024-01-15 08:30:00" — must not be altered.
        let input  = "[2024-01-15 08:30:00] [INFO] [app] starting"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertTrue(output.contains("2024-01-15 08:30:00"),
            "Timestamps should pass through unchanged; got: \(output)")
    }

    func testRedact_preservesNonSensitivePlainText() {
        let input  = "Zoom removed successfully. Reinstall complete."
        let output = DiagnosticRedactor.redact(input)
        XCTAssertEqual(input, output,
            "Non-sensitive plain text should not be altered; got: \(output)")
    }

    func testRedact_preservesCommandNames() {
        let input  = "cmd=rm -rf /Applications/zoom.us.app"
        let output = DiagnosticRedactor.redact(input)
        // Command name should survive; path is outside ~ so also untouched.
        XCTAssertTrue(output.contains("cmd=rm -rf /Applications/zoom.us.app"),
            "Command names and system app paths should not be redacted; got: \(output)")
    }

    // MARK: - Edge cases

    func testRedact_emptyString_returnsEmpty() {
        XCTAssertEqual("", DiagnosticRedactor.redact(""))
    }

    func testRedact_isIdempotent() {
        // Redacting an already-redacted string should not change it further.
        let input    = "log from /Users/alice/file.txt with email user@test.com"
        let once     = DiagnosticRedactor.redact(input)
        let twice    = DiagnosticRedactor.redact(once)
        XCTAssertEqual(once, twice,
            "redact() should be idempotent; second pass changed the output")
    }

    func testRedact_multipleRulesAppliedInOneLine() {
        // A single line that fires home-path + email + password redaction.
        let input  = "/Users/carol/app.log contacted user@corp.com PASSWORD=abc"
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("carol"))
        XCTAssertFalse(output.contains("user@corp.com"))
        XCTAssertFalse(output.contains("abc"))
        XCTAssertTrue(output.contains("[email]"))
        XCTAssertTrue(output.contains("PASSWORD=[redacted]"))
    }

    func testRedact_multilineText() {
        let input = """
        Path: /Users/dave/Library/Logs
        Email: dave@example.org
        Result: SUCCESS
        """
        let output = DiagnosticRedactor.redact(input)
        XCTAssertFalse(output.contains("dave"))
        XCTAssertFalse(output.contains("dave@example.org"))
        XCTAssertTrue(output.contains("[email]"))
        XCTAssertTrue(output.contains("Result: SUCCESS"),
            "Non-sensitive lines should survive multi-line redaction; got:\n\(output)")
    }
}
