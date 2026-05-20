import AppKit
import Foundation

// MARK: - DiagnosticReport

/// Builds the exportable diagnostic report from the on-disk log file.
///
/// Design: the shell script writes the bulk of the diagnostic content to
/// `~/Library/Logs/Zoom Nuke/latest.log` via `_shared_logging.sh`.  This
/// type reads that file, adds an app-side header, optionally redacts it, and
/// presents it to the user via clipboard / save panel / Mail.
struct DiagnosticReport {

    // MARK: - Report generation

    /// Returns the full redacted report text ready for copy or export.
    static func generate(redacted: Bool = true) -> String {
        let rawLog  = readLatestLog()
        let content = rawLog.isEmpty ? "(No diagnostic log found for this session.)" : rawLog
        let text    = header() + content
        return redacted ? DiagnosticRedactor.redact(text) : text
    }

    // MARK: - Actions

    /// Copies the redacted report to the system clipboard.
    static func copyToClipboard() {
        let text = generate(redacted: true)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens an `NSSavePanel` so the user can save the redacted report.
    /// Must be called on the main thread.
    static func exportWithSavePanel() {
        let panel            = NSSavePanel()
        panel.title          = "Export Diagnostic Log"
        panel.nameFieldStringValue = "zoom-nuke-diagnostic.log"
        panel.allowedContentTypes  = [.plainText, .log]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = generate(redacted: true)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Surface the failure — a silent try? leaves the user thinking
                // the export succeeded when the file was never written.
                let alert = NSAlert()
                alert.alertStyle        = .critical
                alert.messageText       = "Export Failed"
                alert.informativeText   = "Could not save the diagnostic log:\n\(error.localizedDescription)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    /// Opens a pre-filled GitHub new-issue page in the default browser.
    ///
    /// Strategy: the full log can be many KB — too large for a URL query string.
    /// Instead we:
    ///   1. Copy the full redacted report to the clipboard automatically.
    ///   2. Open the GitHub new-issue URL with only the diagnostic summary
    ///      block in the body (small enough to survive URL limits).
    ///   3. Show an alert telling the user the full log is on the clipboard
    ///      and to paste it into the issue body.
    static func sendViaMail() {
        let fullReport = generate(redacted: true)

        // Copy full report to clipboard so the user can paste it into the issue.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullReport, forType: .string)

        // Build a compact issue body containing only the summary block.
        let summary = DiagnosticLogger.shared.latestSummary ?? "(No summary available — paste the full log below.)"
        let issueBody = """
        **Describe what you were doing when it failed:**
        <!-- replace this line -->

        **Diagnostic Summary (auto-filled):**
        ```
        \(summary)
        ```

        **Full diagnostic log:**
        <!-- The full log has been copied to your clipboard. Paste it here. -->
        """

        let title       = "Bug report: Zoom Nuke diagnostic"
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let encodedBody  = issueBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? issueBody
        let issueURLString = "https://github.com/chicksonspeed/Zoom-Nuke/issues/new"
                           + "?title=\(encodedTitle)&body=\(encodedBody)"

        var opened = false
        if let url = URL(string: issueURLString) {
            opened = NSWorkspace.shared.open(url)
        }

        // Show a short instruction alert regardless — the user needs to know to paste.
        let alert = NSAlert()
        if opened {
            alert.messageText     = "GitHub Issue Opened"
            alert.informativeText = "The diagnostic summary has been pre-filled in the issue body. "
                                  + "Your full log has been copied to the clipboard — "
                                  + "paste it into the \"Full diagnostic log\" section before submitting."
        } else {
            alert.messageText     = "Could Not Open Browser"
            alert.informativeText = "Your full diagnostic report has been copied to the clipboard. "
                                  + "Open https://github.com/chicksonspeed/Zoom-Nuke/issues/new "
                                  + "and paste it into the issue body."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Log path helpers

    /// Returns the URL of the current session log (`latest.log`), or `nil`.
    static func latestLogURL() -> URL? {
        return DiagnosticLogger.shared.currentLogPath
            ?? DiagnosticLogger.shared.logDirectory?
                .appendingPathComponent("latest.log")
    }

    /// Returns `true` if a readable latest.log exists.
    static func latestLogExists() -> Bool {
        guard let url = latestLogURL() else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    // MARK: - Private

    private static func readLatestLog() -> String {
        guard let url = latestLogURL(),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    private static func header() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                         as? String ?? "unknown"
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(osVer.majorVersion).\(osVer.minorVersion).\(osVer.patchVersion)"
        return """
Zoom Nuke Diagnostic Report
Generated: \(Date())
App Version: \(appVersion)
macOS: \(macOS)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"""
    }
}

// MARK: - UTType helpers

import UniformTypeIdentifiers

private extension UTType {
    static var log: UTType { UTType(filenameExtension: "log") ?? .plainText }
}
