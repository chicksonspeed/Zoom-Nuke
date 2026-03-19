import AppKit
import SwiftUI

// MARK: - Layout Constants
private enum Layout {
    static let windowWidth: CGFloat = 460
    static let windowHeight: CGFloat = 430
    static let shellCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 22
    static let trafficLightSize: CGFloat = 11
    static let statusPillDotSize: CGFloat = 6
    static let titleBarHeight: CGFloat = 33
}

// MARK: - Theme Colors
private enum Theme {
    static let panelBackground = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let titleBarBackground = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let shellBackground = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let successGreen = Color(red: 0.32, green: 0.92, blue: 0.56)
    static let errorRed = Color(red: 0.95, green: 0.44, blue: 0.50)
    static let warningAmber = Color(red: 0.94, green: 0.74, blue: 0.38)
}

private enum CleanMode: String, CaseIterable, Identifiable {
    case standard
    case deep
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard Clean" : "Deep Clean" }
    var subtitle: String {
        self == .standard ? "Removes temporary session data and log files." : "Removes all residual files, caches, and preferences."
    }
    var symbol: String { self == .standard ? "shield.fill" : "flame.fill" }
    var accent: Color {
        self == .standard
            ? Color(red: 0.30, green: 0.66, blue: 1.00)
            : Color(red: 0.69, green: 0.50, blue: 1.00)
    }
}

private enum RunState { case idle, running, success, failure, cancelled }
private enum StatusKind { case info, success, error }

private struct InlineStatus {
    let text: String
    let kind: StatusKind
    var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    var color: Color {
        switch kind {
        case .info: return Color.white.opacity(0.82)
        case .success: return Color(red: 0.45, green: 0.95, blue: 0.62)
        case .error: return Color(red: 0.86, green: 0.45, blue: 0.47)
        }
    }
}

@main
struct ZoomNukeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: Layout.windowWidth, height: Layout.windowHeight)
                .preferredColorScheme(.dark)
        }
    }
}

private func applyWindowStyle(_ window: NSWindow, shouldCenter: Bool) {
    let fixedSize = NSSize(width: Layout.windowWidth, height: Layout.windowHeight)
    window.setContentSize(fixedSize)
    window.minSize = fixedSize
    window.maxSize = fixedSize
    // Keep borderless (prevents native titlebar chrome), but explicitly allow close/minimize.
    window.styleMask = [.borderless, .closable, .miniaturizable, .fullSizeContentView]
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    if #available(macOS 11.0, *) {
        window.titlebarSeparatorStyle = .none
    }
    window.isMovableByWindowBackground = true
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.collectionBehavior.insert(.fullScreenNone)
    window.isReleasedWhenClosed = false

    window.contentView?.wantsLayer = true
    window.contentView?.layer?.cornerRadius = 24
    if #available(macOS 11.0, *) {
        window.contentView?.layer?.cornerCurve = .continuous
    }
    window.contentView?.layer?.masksToBounds = true

    if shouldCenter {
        window.center()
    }
}

private struct TitleBarDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.windows.forEach { applyWindowStyle($0, shouldCenter: true) }
            self.mainWindowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard self != nil, let window = notification.object as? NSWindow else { return }
                applyWindowStyle(window, shouldCenter: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mainWindowObserver {
            NotificationCenter.default.removeObserver(mainWindowObserver)
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            onResolve(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only resolve in makeNSView — avoid redundant applyWindowStyle on every SwiftUI update
    }
}

struct ContentView: View {
    @State private var selectedMode: CleanMode = .standard
    @State private var runState: RunState = .idle
    @State private var status: InlineStatus?
    @State private var liveLogLine: String?
    @State private var resolvedWindow: NSWindow?
    @State private var hoverPrimary = false
    @State private var hoverCancel = false
    @State private var completionPollTimer: Timer?
    @State private var statusFileURL: URL?
    @State private var pidFileURL: URL?
    @State private var cancelRequested = false

    private static let pollInterval: TimeInterval = 0.8
    private static let logPollInterval: TimeInterval = 1.2
    private static let logTailMaxBytes: Int = 4096

    var body: some View {
        ZStack {
            shell.padding(.horizontal, 8).padding(.vertical, 10)
        }
        .background(Color.clear)
        .background(
            WindowAccessor { window in
                resolvedWindow = window
                applyWindowStyle(window, shouldCenter: false)
            }
        )
        .onDisappear { cleanupRunArtifacts() }
    }

    private var shell: some View {
        let shellShape = RoundedRectangle(cornerRadius: Layout.shellCornerRadius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            panel.padding(.horizontal, 18).padding(.top, 56).padding(.bottom, 16)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HStack(spacing: 9) {
                        trafficLight(Color(red: 1.0, green: 0.36, blue: 0.34)) { closeWindow() }
                        trafficLight(Color(red: 0.98, green: 0.75, blue: 0.24)) { NSApp.keyWindow?.miniaturize(nil) }
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 11)

                    TitleBarDragView()
                        .frame(maxWidth: .infinity)
                }
                .frame(height: Layout.titleBarHeight)

                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
            .background(Theme.titleBarBackground)
            .clipShape(shellShape)
        }
        .background(Theme.shellBackground)
        .clipShape(shellShape)
    }

    private var panel: some View {
        let panelShape = RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous)
        return VStack(spacing: 14) {
            header
            modeSection
            runningProgress
            statusBanner
            liveLogBanner
            actionRow
            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.panelBackground)
        .overlay(alignment: .bottom) {
            RadialGradient(
                colors: [selectedMode.accent.opacity(0.26), Color.clear],
                center: .bottom,
                startRadius: 30,
                endRadius: 220
            )
            .clipShape(panelShape)
            .allowsHitTesting(false)
        }
        .clipShape(panelShape)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Zoom Nuke")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.95))
                Text("Clean up residual Zoom sessions safely.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.58))
            }
            Spacer()
            statusPill
        }
        .padding(.top, 2)
    }

    private var statusPill: some View {
        let (label, dot, bg): (String, Color, Color) = {
            switch runState {
            case .idle:
                return ("Ready", Theme.successGreen, Color(red: 0.10, green: 0.22, blue: 0.16).opacity(0.88))
            case .running:
                return ("Running", Color.white.opacity(0.85), Color.white.opacity(0.08))
            case .success:
                return ("Done", Theme.successGreen, Color(red: 0.10, green: 0.22, blue: 0.16).opacity(0.88))
            case .failure:
                return ("Error", Theme.errorRed, Color(red: 0.26, green: 0.12, blue: 0.14).opacity(0.90))
            case .cancelled:
                return ("Cancelled", Theme.warningAmber, Color(red: 0.24, green: 0.18, blue: 0.08).opacity(0.90))
            }
        }()

        return HStack(spacing: 7) {
            Circle().fill(dot).frame(width: Layout.statusPillDotSize, height: Layout.statusPillDotSize)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.90))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(bg))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(label)")
    }

    private func trafficLight(_ activeColor: Color, action: @escaping () -> Void) -> some View {
        TrafficLightButton(activeColor: activeColor, action: action)
    }

    private struct TrafficLightButton: View {
        let activeColor: Color
        let action: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(hovering ? activeColor : Color.white.opacity(0.18))
                    .frame(width: Layout.trafficLightSize, height: Layout.trafficLightSize)
                    .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE CLEANUP MODE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.52))
                .tracking(0.8)

            VStack(spacing: 10) {
                ForEach(CleanMode.allCases) { mode in
                    ModeRow(
                        mode: mode,
                        selected: selectedMode == mode,
                        disabled: runState == .running,
                        accent: primaryAccent
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedMode = mode }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var runningProgress: some View {
        if runState == .running {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cleanup in progress...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.70))
                ProgressView().progressViewStyle(.linear).tint(primaryAccent)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let status {
            HStack(spacing: 8) {
                Image(systemName: status.symbol)
                Text(status.text).lineLimit(2)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(status.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(status.color.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(status.color.opacity(0.36), lineWidth: 0.75))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: startCleanup) {
                ZStack {
                    if runState == .running {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text(primaryButtonTitle).font(.system(size: 13, weight: .semibold))
                        }
                    } else {
                        Text(primaryButtonTitle).font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 11).fill(primaryAccent.opacity(runState == .running ? 0.80 : 1.0))
            )
            .shadow(color: primaryAccent.opacity(0.35), radius: hoverPrimary ? 10 : 5, x: 0, y: 4)
            .onHover { hoverPrimary = $0 }
            .scaleEffect(hoverPrimary && runState != .running ? 1.005 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hoverPrimary)
            .disabled(runState == .running)
            .accessibilityLabel(primaryButtonTitle)
            .accessibilityHint("Starts the Zoom cleanup process in Terminal")

            VStack(spacing: 8) {
                Button(action: cancelOrClose) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(hoverCancel ? 0.80 : 0.52))
                        .frame(height: 22)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { hoverCancel = $0 }
                .animation(.easeOut(duration: 0.14), value: hoverCancel)
                .accessibilityLabel(runState == .running ? "Cancel cleanup" : "Close window")

                Button(action: openLogFile) {
                    Text("Open Log")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .disabled(!FileManager.default.fileExists(atPath: logFilePath))
                .accessibilityLabel("Open log file")
                .accessibilityHint("Opens ~/zoom_fix.log")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color.white.opacity(0.34))
            Button {
                let logURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("zoom_fix.log")
                if FileManager.default.fileExists(atPath: logURL.path) {
                    NSWorkspace.shared.open(logURL)
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
                }
            } label: {
                Text("~/zoom_fix.log")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.44))
                    .underline(false)
            }
            .buttonStyle(.plain)
            .help("Open log file or home folder")
            .accessibilityLabel("Open log file")
            Spacer()
        }
        .padding(.top, 4)
    }

    private var primaryAccent: Color {
        switch runState {
        case .success: return Color(red: 0.44, green: 0.93, blue: 0.61)
        case .failure: return Color(red: 0.82, green: 0.45, blue: 0.48)
        case .cancelled: return Color(red: 0.94, green: 0.74, blue: 0.38)
        case .idle, .running: return selectedMode.accent
        }
    }

    private var primaryButtonTitle: String {
        switch runState {
        case .idle: return "Run Cleanup"
        case .running: return "Running Cleanup"
        case .success: return "Run Again"
        case .failure: return "Retry Cleanup"
        case .cancelled: return "Run Again"
        }
    }

    private func startCleanup() {
        guard runState != .running else { return }
        guard let scriptURL = Bundle.main.url(forResource: "zoom_nuke_overkill", withExtension: "sh") else {
            runState = .failure
            setStatus("Could not find the embedded cleanup script in the app bundle.", kind: .error)
            return
        }
        if !FileManager.default.isExecutableFile(atPath: scriptURL.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }

        cleanupRunArtifacts()
        liveLogLine = nil
        let artifacts = makeRunArtifacts()
        statusFileURL = artifacts.statusURL
        pidFileURL = artifacts.pidURL
        cancelRequested = false
        runState = .running
        setStatus("Launching \(selectedMode.title) in Terminal… enter your password there if prompted.", kind: .info)

        let command = terminalCommand(scriptPath: scriptURL.path, statusPath: artifacts.statusURL.path, pidPath: artifacts.pidURL.path)
        guard launchInTerminal(command: command) else {
            runState = .failure
            setStatus("Could not open Terminal to run cleanup.", kind: .error)
            cleanupRunArtifacts()
            return
        }
        startCompletionPolling()
        startLiveLogPolling()
    }

    private func cancelOrClose() {
        if runState == .running { cancelCleanup() } else { closeWindow() }
    }

    private func cancelCleanup() {
        guard runState == .running else { return }
        cancelRequested = true
        setStatus("Cancel requested. Stopping cleanup in Terminal...", kind: .error)
        guard let shellPID = readShellPID() else { return }

        let groupKill = Process()
        groupKill.executableURL = URL(fileURLWithPath: "/bin/kill")
        groupKill.arguments = ["-TERM", "-\(shellPID)"]
        try? groupKill.run()

        let directKill = Process()
        directKill.executableURL = URL(fileURLWithPath: "/bin/kill")
        directKill.arguments = ["-TERM", "\(shellPID)"]
        try? directKill.run()
    }

    private func setStatus(_ message: String, kind: StatusKind) {
        withAnimation(.easeInOut(duration: 0.18)) {
            status = InlineStatus(text: message, kind: kind)
        }
    }

    private func makeRunArtifacts() -> (statusURL: URL, pidURL: URL) {
        let runID = UUID().uuidString
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return (
            tempRoot.appendingPathComponent("zoom_nuke_status_\(runID).txt"),
            tempRoot.appendingPathComponent("zoom_nuke_pid_\(runID).txt")
        )
    }

    private func terminalCommand(scriptPath: String, statusPath: String, pidPath: String) -> String {
        let deepArg = selectedMode == .deep ? " --deep-clean" : ""
        let modeLine = shellQuote("Mode: \(selectedMode.title)")
        let parts = [
            "clear",
            "echo 'Zoom Nuke.app'",
            "echo \(modeLine)",
            "echo",
            "echo $$ > \(shellQuote(pidPath))",
            "chmod +x \(shellQuote(scriptPath))",
            "/usr/bin/env bash \(shellQuote(scriptPath))\(deepArg)",
            "EXIT_CODE=$?",
            "echo \"$EXIT_CODE\" > \(shellQuote(statusPath))",
            "echo",
            "echo \"Exit code: $EXIT_CODE\"",
            "echo \"Log file: $HOME/zoom_fix.log\""
        ]
        return parts.joined(separator: "; ") + ";"
    }

    private func launchInTerminal(command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(escapeForAppleScript(command))\""
        ]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func startCompletionPolling() {
        completionPollTimer?.invalidate()

        // Timeout after 30 minutes in case the script hangs before writing the status file
        DispatchQueue.main.asyncAfter(deadline: .now() + 30 * 60) {
            guard self.runState == .running else { return }
            self.completionPollTimer?.invalidate()
            self.completionPollTimer = nil
            self.runState = .failure
            self.setStatus("Cleanup timed out after 30 minutes. Check Terminal and ~/zoom_fix.log.", kind: .error)
            self.cleanupRunArtifacts()
        }

        completionPollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            self.checkCompletionStatus()
        }
        if let completionPollTimer { RunLoop.main.add(completionPollTimer, forMode: .common) }
    }

    private func checkCompletionStatus() {
        guard let statusFileURL else { return }
        guard let rawStatus = try? String(contentsOf: statusFileURL, encoding: .utf8) else { return }
        let trimmed = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        completionPollTimer?.invalidate()
        completionPollTimer = nil
        let exitCode = Int32(trimmed) ?? -1
        if cancelRequested {
            runState = .cancelled
            setStatus("Cleanup cancelled. You can run it again any time.", kind: .error)
        } else if exitCode == 0 {
            runState = .success
            setStatus("Cleanup completed successfully. Check ~/zoom_fix.log.", kind: .success)
        } else {
            runState = .failure
            setStatus("Cleanup failed (exit code \(exitCode)). See ~/zoom_fix.log.", kind: .error)
        }
        cleanupRunArtifacts()
    }

    private func readShellPID() -> Int32? {
        guard let pidFileURL else { return nil }
        guard let raw = try? String(contentsOf: pidFileURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(trimmed), pid > 1 else { return nil }
        return pid
    }

    private func cleanupRunArtifacts() {
        completionPollTimer?.invalidate()
        completionPollTimer = nil
        if let statusFileURL { try? FileManager.default.removeItem(at: statusFileURL) }
        if let pidFileURL { try? FileManager.default.removeItem(at: pidFileURL) }
        statusFileURL = nil
        pidFileURL = nil
        liveLogLine = nil
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private var logFilePath: String { (NSHomeDirectory() as NSString).appendingPathComponent("zoom_fix.log") }

    @ViewBuilder
    private var liveLogBanner: some View {
        if runState == .running, let liveLogLine, !liveLogLine.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                Text(liveLogLine)
                    .lineLimit(2)
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.75))
            .transition(.opacity)
            .accessibilityLabel("Latest log output")
        }
    }

    private func startLiveLogPolling() {
        Timer.scheduledTimer(withTimeInterval: Self.logPollInterval, repeats: true) { timer in
            guard self.runState == .running else {
                timer.invalidate()
                return
            }
            self.refreshLiveLogLine()
        }
    }

    private func refreshLiveLogLine() {
        let url = URL(fileURLWithPath: logFilePath)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let data = (try? handle.readToEnd()) ?? Data()
        if data.isEmpty { return }
        let tail = data.suffix(Self.logTailMaxBytes)
        guard let text = String(data: tail, encoding: .utf8) else { return }
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return }

        if last != liveLogLine {
            withAnimation(.easeInOut(duration: 0.12)) {
                liveLogLine = last
            }
        }
    }

    private func openLogFile() {
        let url = URL(fileURLWithPath: logFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func closeWindow() {
        if let resolvedWindow {
            resolvedWindow.close()
        } else {
            NSApp.terminate(nil)
        }
    }
}

private struct ModeRow: View {
    let mode: CleanMode
    let selected: Bool
    let disabled: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selected ? mode.accent : Color.white.opacity(0.45))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? mode.accent.opacity(0.18) : Color.white.opacity(0.05))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(selected ? 0.95 : 0.45))
                    Text(mode.subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(selected ? 0.58 : 0.28))
                        .lineLimit(1)
                }

                Spacer()

                if selected {
                    Circle().fill(accent).frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected
                    ? Color(red: 0.10, green: 0.16, blue: 0.28).opacity(0.80)
                    : Color.white.opacity(hovered && !disabled ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    selected ? accent.opacity(0.75) : Color.white.opacity(0.07),
                    lineWidth: selected ? 1.5 : 0.75
                )
        )
        .onHover { hovered = $0 }
        .disabled(disabled)
        .accessibilityLabel("\(mode.title): \(mode.subtitle)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}
