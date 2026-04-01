import SwiftUI

// MARK: - Layout Constants

enum Layout {
    static let windowWidth: CGFloat = 460
    static let windowHeight: CGFloat = 460
    static let shellCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 22
    static let trafficLightSize: CGFloat = 11
    static let statusPillDotSize: CGFloat = 6
    static let titleBarHeight: CGFloat = 33
}

// MARK: - Theme Colors

enum Theme {
    static let panelBackground    = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let titleBarBackground = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let shellBackground    = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let successGreen       = Color(red: 0.32, green: 0.92, blue: 0.56)
    static let errorRed           = Color(red: 0.95, green: 0.44, blue: 0.50)
    static let warningAmber       = Color(red: 0.94, green: 0.74, blue: 0.38)
}

// MARK: - Clean Mode

enum CleanMode: String, CaseIterable, Identifiable {
    case standard
    case deep

    var id: String { rawValue }

    var title: String {
        self == .standard ? "Standard Clean" : "Deep Clean"
    }

    var subtitle: String {
        self == .standard
            ? "Removes Zoom app, data, caches, and spoofs MAC."
            : "Also wipes residual system artifacts and var/folders caches."
    }

    var symbol: String {
        self == .standard ? "shield.fill" : "flame.fill"
    }

    var accent: Color {
        self == .standard
            ? Color(red: 0.30, green: 0.66, blue: 1.00)
            : Color(red: 0.69, green: 0.50, blue: 1.00)
    }

    /// Arguments passed to the shell script for this mode.
    var scriptArgs: [String] {
        var args = ["--force"]
        if self == .deep { args.append("--deep-clean") }
        return args
    }
}

// MARK: - Run State

enum RunState {
    case idle, running, success, failure, cancelled
}

// MARK: - Status

enum StatusKind {
    case info, success, error
}

struct InlineStatus {
    let text: String
    let kind: StatusKind

    var symbol: String {
        switch kind {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch kind {
        case .info:    return Color.white.opacity(0.82)
        case .success: return Color(red: 0.45, green: 0.95, blue: 0.62)
        case .error:   return Color(red: 0.86, green: 0.45, blue: 0.47)
        }
    }
}
