// DiagnosticLogEntryTests.swift
// ZoomNukeTests — XCTest coverage for DiagnosticLogEntry and LogLevel.
//
// Run:
//   swift test --filter DiagnosticLogEntryTests
//
// These tests only use Foundation.  No AppKit, SwiftUI, or network required.
// All tests are deterministic and safe to run in CI without admin privileges.

import XCTest
@testable import ZoomNukeCore

final class DiagnosticLogEntryTests: XCTestCase {

    // MARK: - LogLevel enum

    func testLogLevel_allCasesHaveCorrectRawValues() {
        XCTAssertEqual(LogLevel.info.rawValue,    "INFO")
        XCTAssertEqual(LogLevel.step.rawValue,    "STEP")
        XCTAssertEqual(LogLevel.success.rawValue, "SUCCESS")
        XCTAssertEqual(LogLevel.warning.rawValue, "WARNING")
        XCTAssertEqual(LogLevel.error.rawValue,   "ERROR")
        XCTAssertEqual(LogLevel.debug.rawValue,   "DEBUG")
    }

    func testLogLevel_allCasesCount() {
        // Guard against accidentally adding a level without updating shell scripts.
        XCTAssertEqual(LogLevel.allCases.count, 6,
            "LogLevel case count changed — update _shared_logging.sh raw values to match")
    }

    func testLogLevel_rawValueRoundTrip() {
        for level in LogLevel.allCases {
            let parsed = LogLevel(rawValue: level.rawValue)
            XCTAssertEqual(parsed, level,
                "LogLevel(\(level.rawValue)) round-trip failed")
        }
    }

    // MARK: - Formatted output structure

    func testFormatted_containsTimestampBrackets() {
        let entry = makeEntry(level: .info, subsystem: "test", message: "hello")
        let output = entry.formatted()
        // Expect:  [YYYY-MM-DD HH:MM:SS]
        let pattern = #"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]"#
        assertMatches(output, pattern: pattern,
            "formatted() should start with a bracketed timestamp")
    }

    func testFormatted_containsLevelInBrackets_allLevels() {
        for level in LogLevel.allCases {
            let entry = makeEntry(level: level, subsystem: "test", message: "msg")
            let output = entry.formatted()
            XCTAssertTrue(output.contains("[\(level.rawValue)]"),
                "formatted() missing [\(level.rawValue)] for level \(level)")
        }
    }

    func testFormatted_containsSubsystemInBrackets() {
        let entry = makeEntry(level: .info, subsystem: "zoom_kill", message: "hello")
        XCTAssertTrue(entry.formatted().contains("[zoom_kill]"))
    }

    func testFormatted_containsMessage() {
        let entry = makeEntry(level: .info, subsystem: "s", message: "Zoom removed successfully")
        XCTAssertTrue(entry.formatted().contains("Zoom removed successfully"))
    }

    func testFormatted_structureOrder() {
        // The canonical format is:  [ts] [LEVEL] [subsystem] message
        let entry = makeEntry(level: .success, subsystem: "install", message: "Done")
        let output = entry.formatted()
        let tsRange    = output.range(of: #"\[\d{4}"#, options: .regularExpression)!
        let levelRange = output.range(of: "[SUCCESS]", options: .literal)!
        let subRange   = output.range(of: "[install]", options: .literal)!
        let msgRange   = output.range(of: "Done", options: .literal)!
        XCTAssertTrue(tsRange.lowerBound    < levelRange.lowerBound)
        XCTAssertTrue(levelRange.lowerBound < subRange.lowerBound)
        XCTAssertTrue(subRange.lowerBound   < msgRange.lowerBound)
    }

    // MARK: - Optional fields

    func testFormatted_includesCommand_whenPresent() {
        let entry = DiagnosticLogEntry(level: .step, subsystem: "cmd_runner",
                                       message: "Running step",
                                       command: "rm -rf /tmp/zoom")
        XCTAssertTrue(entry.formatted().contains("| cmd=rm -rf /tmp/zoom"))
    }

    func testFormatted_includesPath_whenPresent() {
        let entry = DiagnosticLogEntry(level: .info, subsystem: "file",
                                       message: "Checking",
                                       path: "/Applications/zoom.us.app")
        XCTAssertTrue(entry.formatted().contains("| path=/Applications/zoom.us.app"))
    }

    func testFormatted_includesExitCode_whenPresent() {
        let entry = DiagnosticLogEntry(level: .error, subsystem: "cmd_runner",
                                       message: "Failed",
                                       exitCode: 1)
        XCTAssertTrue(entry.formatted().contains("| exit=1"))
    }

    func testFormatted_includesExitCode_zero() {
        let entry = DiagnosticLogEntry(level: .success, subsystem: "cmd_runner",
                                       message: "OK", exitCode: 0)
        XCTAssertTrue(entry.formatted().contains("| exit=0"))
    }

    func testFormatted_includesDuration_withTwoDecimalPlaces() {
        let entry = DiagnosticLogEntry(level: .success, subsystem: "cmd",
                                       message: "Done", duration: 3.5)
        let output = entry.formatted()
        XCTAssertTrue(output.contains("| duration=3.50s"),
            "Duration should be formatted with 2 decimal places; got: \(output)")
    }

    func testFormatted_includesDuration_subSecond() {
        let entry = DiagnosticLogEntry(level: .success, subsystem: "cmd",
                                       message: "Done", duration: 0.07)
        XCTAssertTrue(entry.formatted().contains("| duration=0.07s"))
    }

    func testFormatted_includesSuggestedFix_onNewLine() {
        let entry = DiagnosticLogEntry(level: .error, subsystem: "perm",
                                       message: "Permission denied",
                                       suggestedFix: "Run as admin")
        let output = entry.formatted()
        XCTAssertTrue(output.contains("\n   fix: Run as admin"),
            "Suggested fix should appear on its own line prefixed with 3 spaces")
    }

    func testFormatted_omitsOptionalFields_whenNil() {
        let entry = makeEntry(level: .info, subsystem: "app", message: "clean line")
        let output = entry.formatted()
        XCTAssertFalse(output.contains("| cmd="))
        XCTAssertFalse(output.contains("| path="))
        XCTAssertFalse(output.contains("| exit="))
        XCTAssertFalse(output.contains("| duration="))
        XCTAssertFalse(output.contains("fix:"))
    }

    func testFormatted_allOptionalFields_togetherInOrder() {
        let entry = DiagnosticLogEntry(
            level: .error,
            subsystem: "runner",
            message: "Step failed",
            command:      "curl -L https://zoom.us",
            path:         "/tmp/Zoom.pkg",
            exitCode:     35,
            duration:     12.00,
            suggestedFix: "Check network"
        )
        let output = entry.formatted()
        // Every field must be present
        XCTAssertTrue(output.contains("| cmd=curl -L https://zoom.us"))
        XCTAssertTrue(output.contains("| path=/tmp/Zoom.pkg"))
        XCTAssertTrue(output.contains("| exit=35"))
        XCTAssertTrue(output.contains("| duration=12.00s"))
        XCTAssertTrue(output.contains("fix: Check network"))

        // Fields appear in source order before the fix newline
        let mainLine = output.components(separatedBy: "\n").first!
        let cmdIdx      = mainLine.range(of: "| cmd=")!.lowerBound
        let pathIdx     = mainLine.range(of: "| path=")!.lowerBound
        let exitIdx     = mainLine.range(of: "| exit=")!.lowerBound
        let durationIdx = mainLine.range(of: "| duration=")!.lowerBound
        XCTAssertTrue(cmdIdx < pathIdx)
        XCTAssertTrue(pathIdx < exitIdx)
        XCTAssertTrue(exitIdx < durationIdx)
    }

    // MARK: - Timestamp format

    func testFormatted_timestampMatchesExpectedFormat() {
        // Record time bounds before and after so the timestamp is within range.
        let before = Date()
        let entry  = makeEntry(level: .info, subsystem: "ts", message: "timing check")
        let after  = Date()

        let output = entry.formatted()
        // Extract the bracketed timestamp from the first token.
        guard let tsMatch = output.range(of: #"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]"#,
                                          options: .regularExpression) else {
            XCTFail("No timestamp found in: \(output)")
            return
        }
        // Strip the outer brackets and parse back.
        var tsString = String(output[tsMatch])
        tsString = String(tsString.dropFirst().dropLast())  // remove [ ]

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale     = Locale(identifier: "en_US_POSIX")
        guard let parsedDate = f.date(from: tsString) else {
            XCTFail("Could not parse timestamp: \(tsString)")
            return
        }
        // The timestamp should round to within the before/after bounds
        // (allowing for 1s drift due to second boundary at format granularity).
        XCTAssertTrue(parsedDate >= before.addingTimeInterval(-1),
            "Timestamp \(tsString) is before test started")
        XCTAssertTrue(parsedDate <= after.addingTimeInterval(1),
            "Timestamp \(tsString) is after test ended")
    }

    func testFormatted_timestampUsesEN_US_POSIX_locale() {
        // If the locale leaks through, AM/PM symbols or non-ASCII separators appear.
        let entry  = makeEntry(level: .info, subsystem: "locale", message: "check")
        let output = entry.formatted()
        // Timestamp brackets must contain only digits, dashes, colons, and a space.
        assertMatches(output, pattern: #"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]"#,
            "Timestamp should use 24-hour POSIX format with no locale-specific symbols")
    }

    // MARK: - Identity and immutability

    func testEachEntryGetsUniqueID() {
        let e1 = makeEntry(level: .info, subsystem: "s", message: "m")
        let e2 = makeEntry(level: .info, subsystem: "s", message: "m")
        XCTAssertNotEqual(e1.id, e2.id)
    }

    // MARK: - Helpers

    private func makeEntry(level: LogLevel, subsystem: String, message: String) -> DiagnosticLogEntry {
        DiagnosticLogEntry(level: level, subsystem: subsystem, message: message)
    }

    /// Asserts that `string` contains at least one match for `pattern`.
    private func assertMatches(_ string: String, pattern: String, _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let matched = string.range(of: pattern, options: .regularExpression) != nil
        XCTAssertTrue(matched, "\(message)\n  Input: \(string)\n  Pattern: \(pattern)",
            file: file, line: line)
    }
}
