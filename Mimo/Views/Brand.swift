import SwiftUI

/// Mimo's visual identity: a night-sky palette with one signature violet, rounded display type,
/// and one accent color per character. See the brand sheet in the design mockups.
enum Brand {
    static let violet = Color(hex: 0x7B5CFF)
    static let violetRing = Color(hex: 0x4B3AA8)
    static let night = Color(hex: 0x0E0B24)
    static let deep = Color(hex: 0x1A1442)
    static let dusk = Color(hex: 0x241D55)
    static let indigo = Color(hex: 0x3A3180)
    static let outline = Color(hex: 0x2E2768)
    static let mist = Color(hex: 0xF4F2FF)
    static let lavender = Color(hex: 0xA9A3C9)
    static let ink = Color(hex: 0x17132E)

    /// Rounded display type for names, headings and the wordmark.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension CharacterKind {
    /// The character's signature accent, used for its name, ring and highlights.
    var accentColor: Color { Color(hex: accent) }
}

/// A round icon button in the brand style.
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Brand.mist)
                .frame(width: size, height: size)
                .background(Brand.deep, in: Circle())
                .overlay(Circle().stroke(Brand.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
