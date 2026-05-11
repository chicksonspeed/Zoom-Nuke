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
        liveLines = []
        liveLogVisible = true
        runState = .running
        setStatus("Running \(selectedMode.title)… you may be prompted for your password.", kind: .info)

        // Wire callbacks before launch so no output chunk is missed.
        processManager.onOutput = { [self] text in appendLiveOutput(text) }
        processManager.onExit   = { [self] code in finishCleanup(exitCode: code) }

        processManager.launch(scriptURL: scriptURL, arguments: selectedMode.scriptArgs)
    }

    // MARK: Live output

    func appendLiveOutput(_ text: String) {
        let newLines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !newLines.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.08)) {
            liveLines.append(contentsOf: newLines)
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
            setStatus("Cleanup completed successfully. Check ~/zoom_fix.log.", kind: .success)
        case 130:
            runState = .cancelled
            logFileExists = FileManager.default.fileExists(atPath: ContentView.logFilePath)
            setStatus("Cleanup cancelled. You can run it again any time.", kind: .error)
        default:
            runState = .failure
            logFileExists = FileManager.default.fileExists(atPath: ContentView.logFilePath)
            setStatus("Cleanup failed (exit \(exitCode)). See ~/zoom_fix.log.", kind: .error)
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
