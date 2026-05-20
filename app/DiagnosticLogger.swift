import Foundation

// MARK: - DiagnosticLogger

/// Thread-safe, support-grade logger for Zoom Nuke.
///
/// Responsibilities:
/// - Opens `~/Library/Logs/Zoom Nuke/latest.log` at `beginSession()`.
/// - Writes every raw shell output chunk to that file as it streams in.
/// - Writes structured Swift-side entries (startup, process errors) in the
///   same format used by `_shared_logging.sh` on the shell side.
/// - Archives the previous `latest.log` to a timestamped file each session.
/// - Detects the diagnostic summary block emitted by `write_diagnostic_summary`
///   and makes it available to the UI and export actions.
/// - Publishes `entries` and `latestSummary` on the main queue for SwiftUI.
///
/// Thread safety: all mutations are serialised on a private concurrent queue
/// using barrier writes.  Published properties are only mutated on the main
/// queue so SwiftUI never receives a cross-thread update.
final class DiagnosticLogger: ObservableObject {

    // MARK: - Singleton

    static let shared = DiagnosticLogger()

    // MARK: - Published state (main-queue only)

    @Published private(set) var entries: [DiagnosticLogEntry] = []
    @Published private(set) var latestSummary: String?

    // MARK: - Public read-only

    /// Path to the current session's log file (`latest.log`).
    private(set) var currentLogPath: URL?
    /// `~/Library/Logs/Zoom Nuke/`
    private(set) var logDirectory: URL?

    // MARK: - Private

    private let queue = DispatchQueue(label: "zoom.nuke.diagnosticLogger",
                                      attributes: .concurrent)
    private var fileHandle: FileHandle?
    private var sessionActive = false

    // Summary-block accumulation
    private var summaryLines:    [String] = []
    private var inSummaryBlock = false
    // Tracks whether the shell emitted a summary block.
    // Read on the barrier queue in _endSession — keeps the check on the same
    // queue as all other private mutations, avoiding a cross-queue read of the
    // @Published `latestSummary` (which is only written on the main queue).
    private var _summaryReceived = false

    private static let summaryOpen  = "========== Diagnostic Summary"
    private static let summaryClose = "======================================="

    // MARK: - Init

    private init() { createLogDirectoryIfNeeded() }

    // MARK: - Directory setup

    private func createLogDirectoryIfNeeded() {
        guard let libLogs = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/Zoom Nuke")
        else { return }
        logDirectory = libLogs
        try? FileManager.default.createDirectory(at: libLogs,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Session lifecycle

    /// Call once before launching the cleanup process.
    func beginSession(mode: CleanMode) {
        queue.async(flags: .barrier) { [weak self] in
            self?._beginSession(mode: mode)
        }
    }

    private func _beginSession(mode: CleanMode) {
        guard let dir = logDirectory else { return }

        // Archive any existing latest.log from a previous run.
        let latestURL = dir.appendingPathComponent("latest.log")
        if FileManager.default.fileExists(atPath: latestURL.path) {
            let stamp      = DiagnosticLogger.fileTimestamp()
            let archiveURL = dir.appendingPathComponent("zoom-nuke-\(stamp).log")
            try? FileManager.default.moveItem(at: latestURL, to: archiveURL)
        }

        // Create and open a fresh latest.log.
        FileManager.default.createFile(atPath: latestURL.path, contents: nil)
        fileHandle        = try? FileHandle(forWritingTo: latestURL)
        currentLogPath    = latestURL
        sessionActive     = true
        summaryLines      = []
        inSummaryBlock    = false
        _summaryReceived  = false

        // Reset UI state on the main queue.
        DispatchQueue.main.async { [weak self] in
            self?.entries       = []
            self?.latestSummary = nil
        }

        // Write a file header.
        let header = _sessionHeader(mode: mode)
        _writeRaw(header)

        // Log a Swift-side start entry.
        _append(DiagnosticLogEntry(level: .info, subsystem: "app",
                                   message: "Session started — mode=\(mode.rawValue), log=\(latestURL.path)"))
    }

    /// Call after the process exits.  Writes the summary if the shell didn't
    /// emit one, then closes the file handle.
    func endSession(exitCode: Int32, runState: RunState, mode: CleanMode) {
        queue.async(flags: .barrier) { [weak self] in
            self?._endSession(exitCode: exitCode, runState: runState, mode: mode)
        }
    }

    private func _endSession(exitCode: Int32, runState: RunState, mode: CleanMode) {
        guard sessionActive else { return }

        // Generate a Swift-side summary if the shell did not emit one.
        // Use the barrier-queue flag rather than reading the @Published
        // `latestSummary` across queue boundaries.
        if !_summaryReceived {
            let summary = _buildSummaryBlock(exitCode: exitCode,
                                              runState: runState,
                                              mode: mode)
            _writeRaw("\n" + summary + "\n\n")
            DispatchQueue.main.async { [weak self] in
                self?.latestSummary = summary
            }
        }

        _append(DiagnosticLogEntry(level: .info, subsystem: "app",
                                   message: "Session ended — exit=\(exitCode)"))
        _writeRaw("[Session closed at \(Date())]\n")
        fileHandle?.closeFile()
        fileHandle    = nil
        sessionActive = false
    }

    // MARK: - Output ingestion

    /// Write a raw stdout/stderr chunk to the log file and scan it for
    /// structured entries / summary blocks.  Called for every output chunk
    /// delivered by `CleanupProcessManager`.
    func processOutputChunk(_ text: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self._writeRaw(text)
            // Scan each non-empty line for the summary block.
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                self._scanForSummary(line)
            }
        }
    }

    // MARK: - Structured Swift-side logging

    func log(_ entry: DiagnosticLogEntry) {
        queue.async(flags: .barrier) { [weak self] in
            self?._append(entry)
        }
    }

    // Convenience helpers used by ContentView+Actions.

    func info(_ msg: String, subsystem: String = "app", path: String? = nil) {
        log(DiagnosticLogEntry(level: .info, subsystem: subsystem,
                               message: msg, path: path))
    }

    func step(_ msg: String, subsystem: String = "app", command: String? = nil) {
        log(DiagnosticLogEntry(level: .step, subsystem: subsystem,
                               message: msg, command: command))
    }

    func success(_ msg: String, subsystem: String = "app") {
        log(DiagnosticLogEntry(level: .success, subsystem: subsystem, message: msg))
    }

    func warning(_ msg: String, subsystem: String = "app") {
        log(DiagnosticLogEntry(level: .warning, subsystem: subsystem, message: msg))
    }

    func error(_ msg: String, subsystem: String = "app",
               exitCode: Int? = nil, suggestedFix: String? = nil) {
        log(DiagnosticLogEntry(level: .error, subsystem: subsystem, message: msg,
                               exitCode: exitCode, suggestedFix: suggestedFix))
    }

    // MARK: - Private helpers

    private func _writeRaw(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    private func _append(_ entry: DiagnosticLogEntry) {
        let line = entry.formatted() + "\n"
        _writeRaw(line)
        DispatchQueue.main.async { [weak self] in
            self?.entries.append(entry)
        }
    }

    /// Detect the `========== Diagnostic Summary ==========` block that
    /// `write_diagnostic_summary` in `_shared_logging.sh` emits to stdout.
    private func _scanForSummary(_ line: String) {
        if line.hasPrefix(DiagnosticLogger.summaryOpen) {
            inSummaryBlock = true
            summaryLines   = [line]
            return
        }
        if inSummaryBlock {
            summaryLines.append(line)
            if line.hasPrefix(DiagnosticLogger.summaryClose) {
                inSummaryBlock   = false
                _summaryReceived = true
                let block = summaryLines.joined(separator: "\n")
                DispatchQueue.main.async { [weak self] in
                    self?.latestSummary = block
                }
            }
        }
    }

    // MARK: - Summary generation (Swift-side fallback)

    private func _buildSummaryBlock(exitCode: Int32,
                                     runState: RunState,
                                     mode: CleanMode) -> String {
        let result: String = {
            switch runState {
            case .success:   return "SUCCESS"
            case .failure:   return "FAILED (exit \(exitCode))"
            case .cancelled: return "CANCELLED"
            default:         return "UNKNOWN (exit \(exitCode))"
            }
        }()

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                         as? String ?? "unknown"
        let osVer      = ProcessInfo.processInfo.operatingSystemVersion
        let macOS      = "\(osVer.majorVersion).\(osVer.minorVersion).\(osVer.patchVersion)"
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }()
        let logPath = currentLogPath?.path ?? "unknown"

        return """
========== Diagnostic Summary ==========
Result:         \(result)
Failed Step:    (see log)
Failed Command: (see log)
Exit Code:      \(exitCode)
Likely Cause:   (see log)
Suggested Fix:  (see log)
App Version:    \(appVersion)
Script Version: \(appVersion)
macOS Version:  \(macOS)
Architecture:   \(arch)
Run Mode:       \(mode.rawValue)
Log Path:       \(logPath)
=======================================
"""
    }

    private func _sessionHeader(mode: CleanMode) -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                         as? String ?? "unknown"
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(osVer.majorVersion).\(osVer.minorVersion).\(osVer.patchVersion)"
        return """
zoom-nuke diagnostic log
Started:     \(Date())
App version: \(appVersion)
macOS:       \(macOS)
Mode:        \(mode.rawValue)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"""
    }

    // MARK: - File-name timestamp

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
