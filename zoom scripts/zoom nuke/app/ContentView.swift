import AppKit
import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @State var selectedMode: CleanMode = .standard
    @State var runState: RunState = .idle
    @State var status: InlineStatus?
    @State var resolvedWindow: NSWindow?
    @State var hoverPrimary = false
    @State var hoverCancel = false

    // Live log — fixed-size ring of the last N output lines.
    @State var liveLines: [String] = []
    @State var liveLogVisible = false
    static let maxLiveLines = 80

    @StateObject var processManager = CleanupProcessManagerObservable()

    var logFilePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("zoom_fix.log")
    }

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
        .onDisappear { processManager.terminate() }
    }

    // MARK: - Window Chrome

    var shell: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.shellCornerRadius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            panel.padding(.horizontal, 18).padding(.top, 56).padding(.bottom, 16)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HStack(spacing: 9) {
                        TrafficLightButton(activeColor: Color(red: 1.0, green: 0.36, blue: 0.34)) { closeWindow() }
                        TrafficLightButton(activeColor: Color(red: 0.98, green: 0.75, blue: 0.24)) { NSApp.keyWindow?.miniaturize(nil) }
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 11)
                    TitleBarDragView().frame(maxWidth: .infinity)
                }
                .frame(height: Layout.titleBarHeight)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
            .background(Theme.titleBarBackground)
            .clipShape(shape)
        }
        .background(Theme.shellBackground)
        .clipShape(shape)
    }

    var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous)
        return VStack(spacing: 14) {
            header
            modeSection
            runningProgress
            statusBanner
            liveLogSection
            actionRow
            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.panelBackground)
        .overlay(alignment: .bottom) {
            RadialGradient(
                colors: [selectedMode.accent.opacity(0.26), Color.clear],
                center: .bottom, startRadius: 30, endRadius: 220
            )
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .clipShape(shape)
    }

    // MARK: - Header

    var header: some View {
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

    var statusPill: some View {
        let (label, dot, bg): (String, Color, Color) = {
            switch runState {
            case .idle:
                return ("Ready",     Theme.successGreen,  Color(red: 0.10, green: 0.22, blue: 0.16).opacity(0.88))
            case .running:
                return ("Running",   Color.white.opacity(0.85), Color.white.opacity(0.08))
            case .success:
                return ("Done",      Theme.successGreen,  Color(red: 0.10, green: 0.22, blue: 0.16).opacity(0.88))
            case .failure:
                return ("Error",     Theme.errorRed,      Color(red: 0.26, green: 0.12, blue: 0.14).opacity(0.90))
            case .cancelled:
                return ("Cancelled", Theme.warningAmber,  Color(red: 0.24, green: 0.18, blue: 0.08).opacity(0.90))
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

    // MARK: - Mode Section

    var modeSection: some View {
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

    // MARK: - Progress & Status

    @ViewBuilder
    var runningProgress: some View {
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
    var statusBanner: some View {
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

    // MARK: - Live Log

    @ViewBuilder
    var liveLogSection: some View {
        if !liveLines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.38))
                    Text("LIVE OUTPUT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.38))
                        .tracking(0.8)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { liveLogVisible.toggle() }
                    } label: {
                        Image(systemName: liveLogVisible ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(liveLogVisible ? "Collapse log" : "Expand log")
                }

                if liveLogVisible {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(liveLines.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                        .foregroundColor(lineColor(line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(idx)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .frame(maxHeight: 130)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
                        .onChange(of: liveLines.count) { _ in
                            if let last = liveLines.indices.last {
                                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    if let last = liveLines.last {
                        Text(last)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(lineColor(last).opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                            .transition(.opacity)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    func lineColor(_ line: String) -> Color {
        if line.contains("❌") || line.lowercased().contains("error") || line.lowercased().contains("fail") {
            return Color(red: 0.95, green: 0.55, blue: 0.55)
        } else if line.contains("✅") || line.contains("🎉") {
            return Color(red: 0.55, green: 0.95, blue: 0.70)
        } else if line.contains("⚠️") {
            return Color(red: 0.94, green: 0.80, blue: 0.45)
        }
        return Color.white.opacity(0.62)
    }

    // MARK: - Action Row

    var actionRow: some View {
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
                RoundedRectangle(cornerRadius: 11)
                    .fill(primaryAccent.opacity(runState == .running ? 0.80 : 1.0))
            )
            .shadow(color: primaryAccent.opacity(0.35), radius: hoverPrimary ? 10 : 5, x: 0, y: 4)
            .onHover { hoverPrimary = $0 }
            .scaleEffect(hoverPrimary && runState != .running ? 1.005 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hoverPrimary)
            .disabled(runState == .running)
            .accessibilityLabel(primaryButtonTitle)
            .accessibilityHint("Starts the Zoom cleanup process")

            VStack(spacing: 8) {
                Button(action: cancelOrClose) {
                    Text(runState == .running ? "Cancel" : "Close")
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

    // MARK: - Footer

    var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.34))
            Button {
                let logURL = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("zoom_fix.log")
                if FileManager.default.fileExists(atPath: logURL.path) {
                    NSWorkspace.shared.open(logURL)
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
                }
            } label: {
                Text("~/zoom_fix.log")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.44))
            }
            .buttonStyle(.plain)
            .help("Open log file or home folder")
            .accessibilityLabel("Open log file")
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Computed Helpers

    var primaryAccent: Color {
        switch runState {
        case .success:        return Color(red: 0.44, green: 0.93, blue: 0.61)
        case .failure:        return Color(red: 0.82, green: 0.45, blue: 0.48)
        case .cancelled:      return Color(red: 0.94, green: 0.74, blue: 0.38)
        case .idle, .running: return selectedMode.accent
        }
    }

    var primaryButtonTitle: String {
        switch runState {
        case .idle:      return "Run Cleanup"
        case .running:   return "Running…"
        case .success:   return "Run Again"
        case .failure:   return "Retry Cleanup"
        case .cancelled: return "Run Again"
        }
    }
}
