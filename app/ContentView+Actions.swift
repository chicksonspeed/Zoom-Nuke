import AppKit
import SwiftUI

// MARK: - ContentView Actions

extension ContentView {

    // MARK: Start

    func startCleanup() {
        guard runState != .running else { return }

        // If the user clicked "Run Again" right after cancelling, the 1.5-second
        // deferred SIGTERM might not have fired yet. Cancel it so it doesn't kill
        // the process we are about to launch.
        pendingTerminate?.cancel()
        pendingTerminate = nil

        guard let scriptURL = Bundle.main.url(forResource: "zoom_nuke_overkill", withExtension: "sh") else {
            runState = .failure
            DiagnosticLogger.shared.beginSession(mode: selectedMode)
            DiagnosticLogger.shared.error(
                "Embedded cleanup script not found in app bundle",
                subsystem: "app",
                suggestedFix: "Re-download Zoom Nuke from the official GitHub release page."
            )
            DiagnosticLogger.shared.endSession(exitCode: -1, runState: .failure, mode: selectedMode)
            setStatus("Could not find the embedded cleanup script in the app bundle.", kind: .error)
            return
        }

        // Ensure executable bit is set; dispatched off main to avoid frame hitch.
        DispatchQueue.global(qos: .utility).async {
            if !FileManager.default.isExecutableFile(atPath: scriptURL.path) {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            }
            DispatchQueue.main.async { self._doLaunch(scriptURL: scriptURL) }
        }
    }

    func _doLaunch(scriptURL: URL) {
        liveLines       = []
        cleanupProgress = nil     // reset determinate progress for the new run
        liveLogVisible  = true
        runState        = .running
        setStatus("Running \(selectedMode.title)… you may be prompted for your password.", kind: .info)

        // Begin a new diagnostic session before any output arrives.
        DiagnosticLogger.shared.beginSession(mode: selectedMode)
        DiagnosticLogger.shared.step("Launching cleanup script",
                                      subsystem: "app",
                                      command: scriptURL.lastPathComponent)

        // Wire callbacks before launch so no output chunk is missed.
        processManager.onOutput = { [self] text in appendLiveOutput(text) }
        processManager.onExit   = { [self] code in finishCleanup(exitCode: code) }

        var launchArgs = selectedMode.scriptArgs
        if autoRestoreOnFailure { launchArgs.append("--auto-restore-on-failure") }
        processManager.launch(scriptURL: scriptURL, arguments: launchArgs)
    }

    // MARK: Live output

    private static let progressPrefix = "[PROGRESS] "

    func appendLiveOutput(_ text: String) {
        // Forward every raw chunk to the diagnostic logger (disk write + summary scan).
        DiagnosticLogger.shared.processOutputChunk(text)

        let rawLines = text.components(separatedBy: .newlines)
        var displayLines: [LiveLine] = []

        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse [PROGRESS] N/T label markers and update the progress bar.
            // These lines are not shown in the live log — they're UI control signals.
            if trimmed.hasPrefix(ContentView.progressPrefix) {
                let body = String(trimmed.dropFirst(ContentView.progressPrefix.count))
                // body = "3/8 Stopping Zoom processes"
                if let spaceIdx = body.firstIndex(of: " ") {
                    let ratio = String(body[body.startIndex ..< spaceIdx])
                    let label = String(body[body.index(after: spaceIdx)...])
                    let parts = ratio.split(separator: "/")
                    if parts.count == 2,
                       let step  = Int(parts[0]),
                       let total = Int(parts[1]) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            cleanupProgress = CleanupProgress(step: step,
                                                              total: total,
                                                              label: label)
                        }
                    }
                }
                continue  // don't add progress markers to the visible live log
            }

            displayLines.append(LiveLine(text: trimmed))
        }

        guard !displayLines.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.08)) {
            liveLines.append(contentsOf: displayLines)
            if liveLines.count > ContentView.maxLiveLines {
                liveLines.removeFirst(liveLines.count - ContentView.maxLiveLines)
            }
        }
    }

    // MARK: Finish

    func finishCleanup(exitCode: Int32) {
        processManager.onOutput = nil
        processManager.onExit   = nil

        // If the user already clicked Cancel, don't overwrite that state.
        // The process may have exited naturally while we were waiting for the
        // SIGINT/SIGTERM to land, and we don't want to flash ".success" or
        // ".failure" over a deliberate cancel.
        guard runState != .cancelled else { return }

        switch exitCode {
        case 0:
            runState = .success
            logFileExists = true
            DiagnosticLogger.shared.success("Cleanup completed successfully", subsystem: "app")
            DiagnosticLogger.shared.endSession(exitCode: exitCode, runState: .success, mode: selectedMode)
            setStatus("Cleanup completed successfully. Use \"Copy Log\" to share diagnostics.", kind: .success)
        case 130:
            runState = .cancelled
            logFileExists = FileManager.default.fileExists(atPath: ContentView.logFilePath)
            DiagnosticLogger.shared.warning("Run cancelled by user (SIGINT/exit 130)", subsystem: "app")
            DiagnosticLogger.shared.endSession(exitCode: exitCode, runState: .cancelled, mode: selectedMode)
            setStatus("Cleanup cancelled. You can run it again any time.", kind: .error)
        default:
            runState = .failure
            logFileExists = FileManager.default.fileExists(atPath: ContentView.logFilePath)
            DiagnosticLogger.shared.error(
                "Cleanup failed — exit \(exitCode)",
                subsystem: "app",
                exitCode: Int(exitCode),
                suggestedFix: "Use \"Copy Log\" or \"Export Log\" to send a diagnostic report."
            )
            DiagnosticLogger.shared.endSession(exitCode: exitCode, runState: .failure, mode: selectedMode)
            setStatus("Cleanup failed (exit \(exitCode)). Use \"Copy Log\" to get diagnostics.", kind: .error)
        }
    }

    // MARK: Cancel / Close

    func cancelOrClose() {
        if runState == .running {
            // Nil out callbacks immediately so any in-flight terminationHandler
            // dispatch cannot race with the state we set below.
            processManager.onOutput = nil
            processManager.onExit   = nil

            runState = .cancelled
            setStatus("Cancelling…", kind: .error)
            processManager.interrupt()

            // Give the script a moment to handle SIGINT gracefully, then escalate
            // to SIGTERM. Store the work item so startCleanup() can cancel it if
            // the user immediately clicks "Run Again".
            let work = DispatchWorkItem { [self] in
                self.processManager.terminate()
                self.pendingTerminate = nil
            }
            pendingTerminate = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        } else {
            closeWindow()
        }
    }

    // MARK: Helpers

    func setStatus(_ message: String, kind: StatusKind) {
        withAnimation(.easeInOut(duration: 0.18)) {
            status = InlineStatus(text: message, kind: kind)
        }
    }

    func openLogFile() {
        let url = URL(fileURLWithPath: ContentView.logFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func closeWindow() {
        if let resolvedWindow {
            resolvedWindow.close()
        } else {
            NSApp.windows.first?.close()
        }
    }
}
