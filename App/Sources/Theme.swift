import PokerCore
import SwiftUI

/// The per-device theme, stored as `@AppStorage("theme")`. Each theme has a light and a dark palette.
enum ThemeName: String, CaseIterable {
    case felt, neon, ruby, royal

    var label: String {
        switch self {
        case .felt: "Felt"
        case .neon: "Neon"
        case .ruby: "Rubin"
        case .royal: "Royal"
        }
    }
}

/// The per-device brightness, stored as `@AppStorage("appearance")`. Independent of the theme.
enum Appearance: String, CaseIterable {
    case light, dark, system

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    /// One-time move from the old "felt/dark/system" setting. Call before any `@AppStorage` read.
    /// A stored `theme` is the marker that it ran, so a user's later choice is never overwritten.
    static func migrate(in defaults: UserDefaults) {
        guard defaults.object(forKey: "theme") == nil else { return }
        switch defaults.string(forKey: "appearance") {
        case "felt":
            defaults.set(Appearance.light.rawValue, forKey: "appearance")
            defaults.set(ThemeName.felt.rawValue, forKey: "theme")
        case "dark":
            // Today's dark theme lands on its successor.
            defaults.set(ThemeName.neon.rawValue, forKey: "theme")
        default:
            defaults.set(ThemeName.felt.rawValue, forKey: "theme")
        }
    }
}

#if DEBUG
extension Appearance {
    /// Self-check for `migrate(in:)`, run at launch: the app target has no test target.
    static func checkMigration() {
        // Launch arguments show through every suite and would mask the scratch values.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments["theme"] == nil, arguments["appearance"] == nil else { return }
        let suite = "io.github.mauwii.pokerchipcase.migration-check"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defer { defaults.removePersistentDomain(forName: suite) }
        // stored appearance -> (appearance, theme) after migrate
        let cases: [(String?, String?, String)] = [("felt", "light", "felt"), ("dark", "dark", "neon"), ("system", "system", "felt"), (nil, nil, "felt")]
        for (old, appearance, theme) in cases {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(old, forKey: "appearance")
            migrate(in: defaults)
            assert(defaults.string(forKey: "appearance") == appearance, "migrate: appearance from \(old ?? "nil")")
            assert(defaults.string(forKey: "theme") == theme, "migrate: theme from \(old ?? "nil")")
        }
        // a stored theme is never overwritten
        defaults.set("dark", forKey: "appearance")
        defaults.set("royal", forKey: "theme")
        migrate(in: defaults)
        assert(defaults.string(forKey: "theme") == "royal", "migrate overwrote a stored theme")
    }
}
#endif

/// The per-device card face, stored as `@AppStorage("cardFace")`.
enum CardFace: String, CaseIterable {
    case centered, classic, jumbo, solid

    var label: String { rawValue.capitalized }
}

/// The per-device card back pattern, stored as `@AppStorage("cardBackPattern")`. Any pattern takes any `CardBack` color.
enum CardBackPattern: String, CaseIterable {
    case lattice, medallion, rays, stripes, dots, monogram

    var label: String { rawValue.capitalized }

    /// The monogram letter: the name's first character, uppercased; nil for an empty name.
    static func monogram(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
    }
}

#if DEBUG
extension CardBackPattern {
    /// Self-check for `monogram(_:)`, run at launch: the app target has no test target.
    static func checkMonogram() {
        assert(monogram("  maverick") == "M")
        assert(monogram("Du") == "D")
        assert(monogram(" \n") == nil)
        assert(monogram("") == nil)
        assert(monogram("ßigi") == "SS")
        assert(monogram("🃏 Joker") == "🃏")
    }
}
#endif

/// The per-device card back, stored as `@AppStorage("cardBack")`. Its color is the same in every theme.
enum CardBack: String, CaseIterable {
    case red, blue, green, black, purple

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red: Color(hex: 0xb03a2e)
        case .blue: Color(hex: 0x1f4e8c)
        case .green: Color(hex: 0x1e6b45)
        case .black: Color(hex: 0x1c1c1e)
        case .purple: Color(hex: 0x5b3a8c)
        }
    }
}

/// The ring around the felt. It keeps its material in light and dark; it is what makes a theme recognizable.
struct Rail: Sendable {
    enum Fill: Sendable { case angular([Color], start: Angle), linear([Color]) }
    var fill: Fill
    /// Thin line on the rail's outer edge.
    var edge: Color
    /// Neon only.
    var glow: Color?
    /// Fine concentric wood grain, Felt only.
    var grain: Bool
}

/// Look tokens. The layout is the same for every theme; only these values change.
struct Theme: Sendable {
    /// Three stops of the room's radial gradient behind the table, inner to outer.
    var room: [Color]
    /// The middle room stop, for flat fills: navigation bar, banner.
    var background: Color
    /// Ground of the screens away from the table: lists, forms and sheets.
    var screen: Color
    /// Three stops of the felt's radial gradient, inner to outer.
    var surface: [Color]
    var rail: Rail
    /// The band between felt and rail.
    var cushion: Color
    /// Width of the cushion as a fraction of the table diameter.
    var cushionWidth: CGFloat
    /// The betting line on the felt.
    var line: Color
    var seat: Color
    var seatBorder: Color
    var seatText: Color
    /// Ink: text on the room.
    var text: Color
    /// Pot and bets on the felt.
    var onTable: Color
    /// Light `onTable` text on a light felt gets a soft dark shadow, so it stays readable.
    var onTableShadow: Bool
    /// Red and green text on the seat fill, at 4.5:1: errors and losses, wins.
    var red: Color
    var green: Color
    var muted: Color
    var accent: Color
    var onAccent: Color
    /// Tint for text and controls on room, screen and system material: the accent where it reads at 4.5:1 there,
    /// else the ink. Never used as a button fill.
    var formTint: Color
    var fold: Color
    var onFold: Color
    /// Exactly three chip colors.
    var chips: [Color]
    /// Inner frame of a card back.
    var cardFrame: Color
    /// Card face background.
    var cardFace: Color
    /// Rank and the black suits on a card face.
    var cardText: Color
    /// Hearts, and diamonds unless the four-color deck is on.
    var cardRed: Color
    /// Diamonds in the four-color deck.
    var cardBlue: Color
    /// Clubs in the four-color deck.
    var cardGreen: Color
    /// Edge line of a card face where the drop shadow alone does not set it off; nil for none.
    var cardEdge: Color?
}

extension Theme {
    /// Ink of a suit on this theme's card face.
    func suitColor(_ suit: Card.Suit, fourColor: Bool) -> Color {
        switch suit {
        case .spades: cardText
        case .hearts: cardRed
        case .diamonds: fourColor ? cardBlue : cardRed
        case .clubs: fourColor ? cardGreen : cardText
        }
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = ThemeName.felt.palette(for: .light)
    /// The window's color scheme, which `themed()` picks the palette from; a sheet's own scheme can differ.
    @Entry var stageScheme: ColorScheme = .light
}

extension View {
    /// Sets the chosen theme's palette for the current color scheme, and its form tint.
    func themed() -> some View { modifier(Themed()) }

    /// Theme background, tint and navigation bar for a screen; the last modifier inside its `NavigationStack`.
    /// System controls follow the stage's color scheme. The bar's background visibility is left to the
    /// screen: the table hides it from outside.
    func themedScreen() -> some View { modifier(ThemedScreen()) }

    /// The theme's seat color as the row background of a list or form section.
    func themedRow() -> some View { modifier(ThemedRow()) }
}

private struct ThemedScreen: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.screen.ignoresSafeArea())
            // No foregroundStyle, not even a hierarchical one: in a Form it overrides button tint and the
            // destructive role's red. Section headers set theme.muted themselves.
            .tint(theme.formTint)
            .toolbarBackground(theme.screen, for: .navigationBar)
    }
}

private struct ThemedRow: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View { content.listRowBackground(theme.seat) }
}

private struct Themed: ViewModifier {
    @AppStorage("theme") private var themeName = ThemeName.felt
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = themeName.palette(for: scheme)
        content.environment(\.theme, theme).environment(\.stageScheme, scheme).tint(theme.formTint)
    }
}

/// Full-width table button: accent fill for actions, the theme's fold color for Fold.
struct ThemeButtonStyle: ButtonStyle {
    enum Role { case primary, fold }
    var role: Role

    init(_ role: Role = .primary) { self.role = role }

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, role: role)
    }

    private struct Styled: View {
        let configuration: Configuration
        let role: Role
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.bold()).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(role == .fold ? theme.onFold : theme.onAccent)
                .background(role == .fold ? theme.fold : theme.accent, in: .rect(cornerRadius: 10))
                .opacity(opacity)
        }

        private var opacity: Double {
            if !isEnabled { 0.4 } else if configuration.isPressed { 0.7 } else { 1 }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}
