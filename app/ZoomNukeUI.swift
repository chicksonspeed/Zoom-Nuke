import AppKit
import SwiftUI

private enum CleanMode: String, CaseIterable, Identifiable {
    case standard
    case deep
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard Clean" : "Deep Clean" }
    var subtitle: String {
        self == .standard ? "Balanced reset for most users" : "Aggressive cleanup and\nextra wiping"
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
            ContentView().frame(width: 460, height: 430).preferredColorScheme(.dark)
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
    @State private var completionPollTimer: Timer?
    @State private var statusFileURL: URL?
    @State private var pidFileURL: URL?
    @State private var cancelRequested = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            shell.padding(.horizontal, 8).padding(.vertical, 10)
        }
        .onDisappear { cleanupRunArtifacts() }
    }

    private var shell: some View {
        let shellShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return shellShape
            .fill(.clear)
            .background(.ultraThinMaterial)
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.52))
            .clipShape(shellShape)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.58)).frame(height: 28)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                .clipShape(shellShape)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.white.opacity(0.09), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 58)
                .clipShape(shellShape)
                .allowsHitTesting(false)
            }
            .overlay {
                panel.padding(.horizontal, 12).padding(.top, 40).padding(.bottom, 12)
            }
            .shadow(color: Color.black.opacity(0.62), radius: 22, x: 0, y: 14)
    }

    private var panel: some View {
        let panelShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return VStack(spacing: 16) {
            header
            modeSection
            runningProgress
            statusBanner
            actionRow
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(.thinMaterial)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.21, blue: 0.30).opacity(0.78),
                    Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 84)
            .clipShape(panelShape)
            .allowsHitTesting(false)
        }
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
        .shadow(color: Color.black.opacity(0.42), radius: 14, x: 0, y: 10)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                trafficLight(Color(red: 1.0, green: 0.36, blue: 0.34)) { NSApp.keyWindow?.performClose(nil) }
                trafficLight(Color(red: 0.98, green: 0.75, blue: 0.24)) { NSApp.keyWindow?.miniaturize(nil) }
                trafficLight(Color(red: 0.35, green: 0.82, blue: 0.36)) { NSApp.keyWindow?.performZoom(nil) }
            }
            Spacer()
            VStack(spacing: 4) {
                Text("Zoom Nuke").font(.system(size: 18, weight: .semibold)).foregroundColor(Color.white.opacity(0.95))
                Text("macOS Cleanup Utility").font(.system(size: 11, weight: .medium)).foregroundColor(Color.white.opacity(0.60))
            }
            Spacer()
            Color.clear.frame(width: 44, height: 12)
        }
    }

    private func trafficLight(_ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color).frame(width: 11, height: 11).overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose cleanup mode").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.white.opacity(0.75))
            HStack(spacing: 10) {
                ForEach(CleanMode.allCases) { mode in
                    ModeCard(mode: mode, selected: selectedMode == mode, disabled: runState == .running) {
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
                Text("Cleanup in progress...").font(.system(size: 12, weight: .semibold)).foregroundColor(Color.white.opacity(0.74))
                ProgressView().progressViewStyle(.linear).tint(primaryAccent)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let status {
            HStack(spacing: 8) { Image(systemName: status.symbol); Text(status.text).lineLimit(2) }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(status.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(status.color.opacity(0.13)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(status.color.opacity(0.36), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: startCleanup) {
                HStack(spacing: 8) {
                    if runState == .running { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: primaryButtonSymbol).font(.system(size: 14, weight: .semibold)) }
                    Text(primaryButtonTitle).font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(
                    LinearGradient(
                        colors: [primaryAccent.opacity(runState == .running ? 0.80 : 0.95), primaryAccent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: primaryAccent.opacity(hoverPrimary || runState == .running ? 0.72 : 0.46), radius: hoverPrimary || runState == .running ? 26 : 14, x: 0, y: 12)
            .onHover { hoverPrimary = $0 }
            .scaleEffect(hoverPrimary && runState != .running ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hoverPrimary)
            .disabled(runState == .running)

            Button(action: cancelOrClose) {
                HStack(spacing: 7) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    Text("Cancel").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Color.white.opacity(0.90))
                .frame(width: 96, height: 40)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(
                    runState == .running
                        ? Color(red: 0.36, green: 0.15, blue: 0.17).opacity(0.88)
                        : Color(red: 0.20, green: 0.22, blue: 0.28)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(
                    runState == .running
                        ? Color(red: 0.86, green: 0.45, blue: 0.47).opacity(0.56)
                        : Color.white.opacity(0.16),
                    lineWidth: 1
                )
            )
            .shadow(color: Color.black.opacity(hoverCancel ? 0.35 : 0.18), radius: hoverCancel ? 12 : 7, x: 0, y: 8)
            .onHover { hoverCancel = $0 }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundColor(Color.white.opacity(0.40))
            Text("Logs:  ~/zoom_fix.log").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(Color.white.opacity(0.56))
            Spacer()
        }
        .padding(.top, 3)
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
    private var primaryButtonSymbol: String {
        switch runState {
        case .idle: return "bolt.fill"
        case .running: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .failure: return "arrow.clockwise.circle.fill"
        case .cancelled: return "arrow.counterclockwise.circle.fill"
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
        let artifacts = makeRunArtifacts()
        statusFileURL = artifacts.statusURL
        pidFileURL = artifacts.pidURL
        cancelRequested = false
        runState = .running
        setStatus("Launching \(selectedMode.title) in Terminal...", kind: .info)

        let command = terminalCommand(scriptPath: scriptURL.path, statusPath: artifacts.statusURL.path, pidPath: artifacts.pidURL.path)
        guard launchInTerminal(command: command) else {
            runState = .failure
            setStatus("Could not open Terminal to run cleanup.", kind: .error)
            cleanupRunArtifacts()
            return
        }
        startCompletionPolling()
    }

    private func cancelOrClose() {
        if runState == .running { cancelCleanup() } else { NSApp.keyWindow?.performClose(nil) }
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
        let parts = [
            "clear",
            "echo 'Zoom Nuke.app'",
            "echo 'Mode: \(selectedMode.title)'",
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
        completionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in checkCompletionStatus() }
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
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
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
                    Image(systemName: mode.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selected ? mode.accent : Color.white.opacity(0.78))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(mode.accent.opacity(selected ? 0.28 : 0.12)))
                        .shadow(color: mode.accent.opacity(selected ? 0.58 : 0.0), radius: 10)
                    Spacer()
                    if selected {
                        ZStack {
                            Circle().fill(mode.accent).frame(width: 15, height: 15)
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                        }
                    }
                }
                Text(mode.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Color.white.opacity(0.95))
                Text(mode.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.63))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(
                    LinearGradient(
                        colors: [Color.white.opacity(selected ? 0.08 : 0.05), Color.white.opacity(selected ? 0.03 : 0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(
                    selected ? mode.accent.opacity(0.95) : Color.white.opacity(0.14),
                    lineWidth: selected ? 2 : 1
                )
            )
            .shadow(
                color: selected ? mode.accent.opacity(0.44) : Color.black.opacity(hovered ? 0.25 : 0.14),
                radius: selected ? 16 : (hovered ? 10 : 7),
                x: 0,
                y: 7
            )
            .scaleEffect(hovered && !disabled ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.16), value: hovered)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
    }
}
