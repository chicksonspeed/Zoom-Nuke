import AppKit
import SwiftUI

// MARK: - ContentView Actions

extension ContentView {

    // MARK: Start

    func startCleanup() {
        guard runState != .running else { return }

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

        switch exitCode {
        case 0:
            runState = .success
            setStatus("Cleanup completed successfully. Check ~/zoom_fix.log.", kind: .success)
        case 130:
            runState = .cancelled
            setStatus("Cleanup cancelled. You can run it again any time.", kind: .error)
        default:
            runState = .failure
            setStatus("Cleanup failed (exit \(exitCode)). See ~/zoom_fix.log.", kind: .error)
        }
    }

    // MARK: Cancel / Close

    func cancelOrClose() {
        if runState == .running {
            runState = .cancelled
            setStatus("Cancelling…", kind: .error)
            processManager.interrupt()
            // Give the script a moment to handle SIGINT, then escalate to SIGTERM.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.processManager.terminate()
            }
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
        let url = URL(fileURLWithPath: logFilePath)
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
