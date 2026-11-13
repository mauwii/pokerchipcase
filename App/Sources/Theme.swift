import SwiftUI

/// The per-device appearance setting, stored as `@AppStorage("appearance")`.
enum Appearance: String, CaseIterable {
    case felt, dark, system

    var label: String {
        switch self {
        case .felt: "Felt"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .felt: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// Look tokens. The layout is the same for every theme; only these values change.
struct Theme: Sendable {
    var background: Color
    /// Inner and outer stop of the table's radial gradient.
    var surface: [Color]
    var rim: Color
    var accent: Color
    var seat: Color
    var text: Color
    var muted: Color
    var fold: Color
    /// Exactly three chip colors.
    var chips: [Color]

    static let felt = Theme(
        background: Color(hex: 0x3b2414), surface: [Color(hex: 0x2f8a4e), Color(hex: 0x1d5e33)], rim: Color(hex: 0x6b3f1d),
        accent: Color(hex: 0xe8c15a), seat: .black.opacity(0.45), text: Color(hex: 0xf3e9d2), muted: Color(hex: 0xc9b99a),
        fold: Color(hex: 0x7a2a1f), chips: [Color(hex: 0xc0392b), Color(hex: 0x2c3e50), Color(hex: 0x27ae60)])

    static let dark = Theme(
        background: Color(hex: 0x0d0f14), surface: [Color(hex: 0x171a22), Color(hex: 0x171a22)], rim: Color(hex: 0x232733),
        accent: Color(hex: 0x38e1b0), seat: Color(hex: 0x232733), text: Color(hex: 0xe8eaf0), muted: Color(hex: 0x8a90a2),
        fold: Color(hex: 0x2a2e3a), chips: [Color(hex: 0x38e1b0), Color(hex: 0x5b6cff), Color(hex: 0xff9f68)])
}

extension EnvironmentValues {
    @Entry var theme: Theme = .felt
}

extension View {
    /// Sets the theme that matches the current color scheme, and its accent as the tint.
    func themed() -> some View { modifier(Themed()) }
}

private struct Themed: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme: Theme = scheme == .dark ? .dark : .felt
        content.environment(\.theme, theme).tint(theme.accent)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}
