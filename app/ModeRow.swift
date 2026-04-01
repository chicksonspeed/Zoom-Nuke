import SwiftUI

// MARK: - Traffic Light Button

struct TrafficLightButton: View {
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

// MARK: - Mode Row

struct ModeRow: View {
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
        .onHover { hovered = disabled ? false : $0 }
        // Reset hover state when the row transitions from disabled → enabled
        // so it doesn't appear hovered until the cursor moves again.
        .onChange(of: disabled) { isDisabled in
            if isDisabled { hovered = false }
        }
        .disabled(disabled)
        .accessibilityLabel("\(mode.title): \(mode.subtitle)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}
