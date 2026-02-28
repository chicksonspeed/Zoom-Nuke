import AppKit
import SwiftUI

private enum CleanMode: String, CaseIterable, Identifiable {
    case standard
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard Clean"
        case .deep:
            return "Deep Clean"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            return "Balanced reset for most users"
        case .deep:
            return "Aggressive cleanup and extra wiping"
        }
    }

    var iconName: String {
        switch self {
        case .standard:
            return "shield.lefthalf.filled"
        case .deep:
            return "flame.fill"
        }
    }

    var accent: Color {
        switch self {
        case .standard:
            return Color(red: 0.30, green: 0.66, blue: 1.00)
        case .deep:
            return Color(red: 0.71, green: 0.49, blue: 1.00)
        }
    }
}

private enum RunState {
    case idle
    case running
    case success
    case failure
    case cancelled
}

private enum StatusKind {
    case info
    case success
    case error
}

private struct InlineStatus {
    let text: String
    let kind: StatusKind

    var color: Color {
        switch kind {
        case .info:
            return Color.white.opacity(0.84)
        case .success:
            return Color(red: 0.45, green: 0.95, blue: 0.62)
        case .error:
            return Color(red: 0.86, green: 0.45, blue: 0.47)
        }
    }

    var symbol: String {
        switch kind {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

@main
struct ZoomNukeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 460, height: 430)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }

            let fixedSize = NSSize(width: 460, height: 430)
            window.setContentSize(fixedSize)
            window.minSize = fixedSize
            window.maxSize = fixedSize
            window.styleMask.remove(.resizable)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.center()
        }
    }
}

struct ContentView: View {
    @State private var selectedMode: CleanMode = .standard
    @State private var runState: RunState = .idle
    @State private var status: InlineStatus?
    @State private var hoverPrimary = false
    @State private var hoverCancel = false
    @State private var cancelRequested = false
    @State private var completionPollTimer: Timer?
    @State private var statusFileURL: URL?
    @State private var pidFileURL: URL?

    private let panelCornerRadius: CGFloat = 24

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.07),
                    Color(red: 0.07, green: 0.07, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    selectedMode.accent.opacity(0.20),
                    Color.clear
                ],
                center: .top,
                startRadius: 10,
                endRadius: 260
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.13, blue: 0.18),
                            Color(red: 0.08, green: 0.09, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.11), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: panelCornerRadius - 4, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .padding(4)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.09),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .mask(
                            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        )
                }
                .shadow(color: Color.black.opacity(0.55), radius: 28, x: 0, y: 20)
                .padding(14)

            VStack(spacing: 18) {
                header
                modePicker
                runningProgress
                statusBanner
                actionRow
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onDisappear {
            completionPollTimer?.invalidate()
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                trafficLight(color: Color(red: 1.0, green: 0.36, blue: 0.34)) {
                    NSApp.keyWindow?.performClose(nil)
                }
                trafficLight(color: Color(red: 0.98, green: 0.75, blue: 0.24)) {
                    NSApp.keyWindow?.miniaturize(nil)
                }
                trafficLight(color: Color(red: 0.35, green: 0.82, blue: 0.36)) {
                    NSApp.keyWindow?.performZoom(nil)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Text("Zoom Nuke")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("macOS Cleanup Utility")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.58))
            }

            Spacer()
            Color.clear.frame(width: 44, height: 12)
        }
    }

    private func trafficLight(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.35), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose cleanup mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.76))

            HStack(spacing: 12) {
                ForEach(CleanMode.allCases) { mode in
                    ModeCard(
                        mode: mode,
                        selected: selectedMode == mode,
                        disabled: runState == .running,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMode = mode
                            }
                        }
                    )
                }
            }
        }
        .opacity(runState == .running ? 0.92 : 1)
    }

    @ViewBuilder
    private var runningProgress: some View {
        if runState == .running {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cleanup in progress...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.72))
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(primaryAccent)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let status {
            HStack(spacing: 8) {
                Image(systemName: status.symbol)
                    .foregroundColor(status.color)
                Text(status.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(status.color)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(status.color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(status.color.opacity(0.3), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: startCleanup) {
                HStack(spacing: 8) {
                    if runState == .running {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: primaryButtonSymbol)
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Text(primaryButtonTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                primaryAccent.opacity(runState == .running ? 0.68 : 0.92),
                                primaryAccent.opacity(0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(
                color: primaryAccent.opacity(hoverPrimary || runState == .running ? 0.85 : 0.46),
                radius: hoverPrimary || runState == .running ? 24 : 12,
                x: 0,
                y: 10
            )
            .scaleEffect(hoverPrimary && runState != .running ? 1.01 : 1)
            .animation(.easeOut(duration: 0.2), value: hoverPrimary)
            .animation(.easeInOut(duration: 0.2), value: runState)
            .onHover { hovering in
                hoverPrimary = hovering
            }
            .disabled(runState == .running)

            Button(action: cancelOrClose) {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 94)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .foregroundColor(Color.white.opacity(0.9))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cancelBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        runState == .running ? Color(red: 0.86, green: 0.45, blue: 0.47).opacity(0.55) : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: runState == .running ? Color(red: 0.86, green: 0.45, blue: 0.47).opacity(hoverCancel ? 0.55 : 0.35) : Color.black.opacity(0.18),
                radius: hoverCancel ? 14 : 8,
                x: 0,
                y: 8
            )
            .onHover { hovering in
                hoverCancel = hovering
            }
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundColor(Color.white.opacity(0.48))
            Text("Logs: ~/zoom_fix.log")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.58))
            Spacer()
        }
        .padding(.top, 2)
    }

    private var primaryAccent: Color {
        switch runState {
        case .success:
            return Color(red: 0.44, green: 0.93, blue: 0.61)
        case .failure:
            return Color(red: 0.82, green: 0.45, blue: 0.48)
        case .cancelled:
            return Color(red: 0.94, green: 0.74, blue: 0.38)
        case .idle, .running:
            return selectedMode.accent
        }
    }

    private var cancelBackgroundColor: Color {
        if runState == .running {
            return Color(red: 0.40, green: 0.15, blue: 0.18).opacity(0.85)
        }
        return Color.white.opacity(0.08)
    }

    private var primaryButtonTitle: String {
        switch runState {
        case .idle:
            return "Run Cleanup"
        case .running:
            return "Running Cleanup"
        case .success:
            return "Run Again"
        case .failure:
            return "Retry Cleanup"
        case .cancelled:
            return "Run Again"
        }
    }

    private var primaryButtonSymbol: String {
        switch runState {
        case .idle:
            return "bolt.fill"
        case .running:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "arrow.clockwise.circle.fill"
        case .cancelled:
            return "arrow.counterclockwise.circle.fill"
        }
    }

    private func startCleanup() {
        guard runState != .running else { return }
        guard let scriptURL = Bundle.main.url(forResource: "Screw1132_Overkill", withExtension: "sh") else {
            runState = .failure
            setStatus("Could not find the embedded cleanup script in the app bundle.", kind: .error)
            return
        }

        if !FileManager.default.isExecutableFile(atPath: scriptURL.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }

        cleanupRunArtifacts()

        let runArtifacts = makeRunArtifacts()
        statusFileURL = runArtifacts.statusURL
        pidFileURL = runArtifacts.pidURL

        cancelRequested = false
        runState = .running
        setStatus("Launching \(selectedMode.title) in Terminal...", kind: .info)

        let command = terminalCommand(
            scriptPath: scriptURL.path,
            statusPath: runArtifacts.statusURL.path,
            pidPath: runArtifacts.pidURL.path
        )

        guard launchInTerminal(command: command) else {
            runState = .failure
            setStatus("Could not open Terminal to run cleanup.", kind: .error)
            cleanupRunArtifacts()
            return
        }

        startCompletionPolling()
    }

    private func cancelOrClose() {
        if runState == .running {
            cancelCleanup()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            status = InlineStatus(text: message, kind: kind)
        }
    }

    private func makeRunArtifacts() -> (statusURL: URL, pidURL: URL) {
        let runID = UUID().uuidString
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let statusURL = tempRoot.appendingPathComponent("zoom_nuke_status_\(runID).txt")
        let pidURL = tempRoot.appendingPathComponent("zoom_nuke_pid_\(runID).txt")
        return (statusURL, pidURL)
    }

    private func terminalCommand(scriptPath: String, statusPath: String, pidPath: String) -> String {
        let quotedScript = shellQuote(scriptPath)
        let quotedStatus = shellQuote(statusPath)
        let quotedPid = shellQuote(pidPath)
        let deepArg = selectedMode == .deep ? " --deep-clean" : ""

        return "clear; " +
            "echo 'Zoom Nuke.app'; " +
            "echo 'Mode: \(selectedMode.title)'; " +
            "echo; " +
            "echo $$ > \(quotedPid); " +
            "chmod +x \(quotedScript); " +
            "/usr/bin/env bash \(quotedScript)\(deepArg); " +
            "EXIT_CODE=$?; " +
            "echo \"$EXIT_CODE\" > \(quotedStatus); " +
            "echo; " +
            "echo \"Exit code: $EXIT_CODE\"; " +
            "echo \"Log file: $HOME/zoom_fix.log\";"
    }

    private func launchInTerminal(command: String) -> Bool {
        let escapedCommand = escapeForAppleScript(command)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(escapedCommand)\""
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
        completionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            checkCompletionStatus()
        }
        if let completionPollTimer {
            RunLoop.main.add(completionPollTimer, forMode: .common)
        }
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
            setStatus("Cleanup completed successfully. Check ~/zoom_fix.log for details.", kind: .success)
        } else {
            runState = .failure
            setStatus("Cleanup failed (exit code \(exitCode)). See ~/zoom_fix.log.", kind: .error)
        }

        cleanupRunArtifacts()
    }

    private func readShellPID() -> Int32? {
        guard let pidFileURL else { return nil }
        guard let rawPID = try? String(contentsOf: pidFileURL, encoding: .utf8) else { return nil }
        let trimmed = rawPID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedPID = Int32(trimmed), parsedPID > 1 else { return nil }
        return parsedPID
    }

    private func cleanupRunArtifacts() {
        completionPollTimer?.invalidate()
        completionPollTimer = nil

        if let statusFileURL {
            try? FileManager.default.removeItem(at: statusFileURL)
        }
        if let pidFileURL {
            try? FileManager.default.removeItem(at: pidFileURL)
        }

        self.statusFileURL = nil
        self.pidFileURL = nil
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct ModeCard: View {
    let mode: CleanMode
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selected ? mode.accent : Color.white.opacity(0.84))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(mode.accent.opacity(selected ? 0.30 : 0.12))
                        )
                        .shadow(color: mode.accent.opacity(selected ? 0.65 : 0), radius: 12)

                    Spacer()

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(mode.accent)
                            .transition(.opacity)
                    }
                }

                Text(mode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.95))

                Text(mode.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.58))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(selected ? 0.09 : 0.05),
                                Color.white.opacity(selected ? 0.03 : 0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? mode.accent.opacity(0.95) : Color.white.opacity(0.15),
                        lineWidth: selected ? 2 : 1
                    )
            )
            .shadow(
                color: selected ? mode.accent.opacity(0.48) : Color.black.opacity(hovered ? 0.28 : 0.18),
                radius: selected ? 18 : (hovered ? 12 : 8),
                y: 8
            )
            .scaleEffect(hovered && !disabled ? 1.01 : 1)
            .animation(.easeOut(duration: 0.18), value: hovered)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.85 : 1)
        .onHover { hovering in
            hovered = hovering
        }
    }
}
