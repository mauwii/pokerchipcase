import SwiftUI

extension ThemeName {
    /// The palette for a stage: `.dark` gives the dark one, anything else the light one.
    func palette(for scheme: ColorScheme) -> Theme {
        let dark = scheme == .dark
        switch self {
        case .felt: return dark ? .feltDark : .feltLight
        case .neon: return dark ? .neonDark : .neonLight
        case .ruby: return dark ? .rubyDark : .rubyLight
        case .royal: return dark ? .royalDark : .royalLight
        }
    }
}

private let gold = Color(hex: 0xe8c15a)
private let goldInk = Color(hex: 0x2a1a0c)
private let classicChips = [Color(hex: 0xc0392b), Color(hex: 0x2c3e50), Color(hex: 0x27ae60)]
/// Royal swaps the navy chip for white: navy vanishes on the navy felt.
private let royalChips = [Color(hex: 0xc0392b), Color(hex: 0xf2f4f7), Color(hex: 0x27ae60)]
private let neonChips = [Color(hex: 0x38e1b0), Color(hex: 0x5b6cff), Color(hex: 0xff9f68)]
/// Card face ground, suit inks (blue and green only for the four-color deck) and an optional face edge.
private typealias CardInk = (face: Color, text: Color, red: Color, blue: Color, green: Color, edge: Color?)
private let fourColorBlue = Color(hex: 0x1f5fbf)
private let fourColorGreen = Color(hex: 0x1b7a40)
/// Felt, Rubin and Royal share the cream card.
private let cream: CardInk = (Color(hex: 0xf6efdf), Color(hex: 0x16181d), Color(hex: 0xc0392b), fourColorBlue, fourColorGreen, nil)

private extension Rail {
    static let wood = Rail(
        fill: .angular(
            [0x7a4820, 0xb9793a, 0x6a3d1a, 0xc58a45, 0x74441e, 0xb17338, 0x7a4820].map { Color(hex: $0) },
            start: .degrees(20)),
        edge: Color(hex: 0xffe1aa).opacity(0.55), glow: nil, grain: true)

    static let leather = Rail(
        fill: .linear([Color(hex: 0x2b2b2e), Color(hex: 0x0c0c0d), Color(hex: 0x2a2a2d)]),
        edge: gold.opacity(0.85), glow: nil, grain: false)

    static func chrome(_ stops: [UInt32]) -> Rail {
        Rail(fill: .angular((stops + [stops[0]]).map { Color(hex: $0) }, start: .degrees(30)),
             edge: Color.white.opacity(0.7), glow: nil, grain: false)
    }
}

/// Per sRGB channel `ink · opacity + ground · (1 − opacity)`, rounded: the opaque look of translucent ink on a ground.
private func blend(_ ink: UInt32, over ground: UInt32, _ opacity: Double) -> UInt32 {
    [16, 8, 0].reduce(0) { result, shift in
        let i = Double((ink >> shift) & 0xff)
        let g = Double((ground >> shift) & 0xff)
        return result << 8 | UInt32((i * opacity + g * (1 - opacity)).rounded())
    }
}

private extension Theme {
    /// Fills the tokens every palette derives the same way: background and screen are the middle room stop,
    /// muted is the ink at `mutedOpacity` over the middle room stop, blended to an opaque color (light stages pass
    /// a higher one to stay at 4.5:1 on the screen).
    /// formTint defaults to the accent; where that falls below 4.5:1 on the room, the palette passes its ink.
    /// The system red and green read on a dark seat fill; a light one (`lightSeat`) gets darker ones.
    init(
        room: [UInt32], surface: [UInt32], rail: Rail, cushion: UInt32, cushionWidth: CGFloat = 0.01, line: Color,
        // Opaque: the audit fails text on a translucent fill whatever the pixels show (#148).
        seat: Color, seatBorder: Color, seatText: UInt32, text: UInt32, onTable: UInt32, onTableShadow: Bool = false,
        lightSeat: Bool = false, mutedOpacity: Double = 0.65,
        accent: Color, onAccent: Color, formTint: Color? = nil, fold: UInt32, onFold: UInt32 = 0xffffff,
        chips: [Color] = classicChips, card: CardInk = cream
    ) {
        let muted = Color(hex: blend(text, over: room[1], mutedOpacity))
        let room = room.map { Color(hex: $0) }
        let text = Color(hex: text)
        self.init(
            room: room, background: room[1], screen: room[1], surface: surface.map { Color(hex: $0) }, rail: rail,
            cushion: Color(hex: cushion), cushionWidth: cushionWidth, line: line,
            seat: seat, seatBorder: seatBorder, seatText: Color(hex: seatText),
            text: text, onTable: Color(hex: onTable), onTableShadow: onTableShadow,
            red: lightSeat ? Color(hex: 0xc0392b) : .red, green: lightSeat ? Color(hex: 0x1e7a3a) : .green,
            muted: muted,
            accent: accent, onAccent: onAccent, formTint: formTint ?? accent,
            fold: Color(hex: fold), onFold: Color(hex: onFold), chips: chips,
            cardFrame: .white, cardFace: card.face, cardText: card.text, cardRed: card.red,
            cardBlue: card.blue, cardGreen: card.green, cardEdge: card.edge)
    }

    static let feltLight = Theme(
        room: [0x8fd0c6, 0x57a9a0, 0x36877f], surface: [0x5fcf86, 0x3aa862, 0x2b8a4e], rail: .wood, cushion: 0x2a8a50,
        line: gold.opacity(0.7), seat: Color(hex: 0xfffcf4), seatBorder: Color(hex: 0x3c280a).opacity(0.25),
        seatText: 0x1c2a22, text: 0x062522, onTable: 0x062522, lightSeat: true, mutedOpacity: 0.9,
        accent: gold, onAccent: goldInk, formTint: Color(hex: 0x062522), fold: 0xc0483a)

    static let feltDark = Theme(
        room: [0x14555a, 0x0a3136, 0x031518], surface: [0x2a8a4f, 0x145030, 0x0a2e1b], rail: .wood, cushion: 0x072414,
        line: gold.opacity(0.7), seat: Color(hex: 0x020806), seatBorder: gold.opacity(0.3),
        seatText: 0xf3efe4, text: 0xe6f2ee, onTable: 0xf6f1e4,
        accent: gold, onAccent: goldInk, fold: 0x7a2a1f)

    static let neonLight = Theme(
        room: [0xc9d1dc, 0xa2adbe, 0x7f8ca1], surface: [0xf4f6fa, 0xe3e8f0, 0xd0d7e2],
        rail: Rail(fill: .linear([Color(hex: 0x4a5366), Color(hex: 0x262c3a)]), edge: Color(hex: 0x1fd19f),
                   glow: Color(hex: 0x12b88a).opacity(0.5), grain: false),
        cushion: 0xaab3c2,
        line: Color(hex: 0x12b88a).opacity(0.55), seat: Color.white, seatBorder: Color(hex: 0x1a2233).opacity(0.18),
        seatText: 0x1a2233, text: 0x1a2233, onTable: 0x1a2233, lightSeat: true, mutedOpacity: 0.9,
        accent: Color(hex: 0x12b88a), onAccent: Color(hex: 0x06110d), formTint: Color(hex: 0x1a2233), fold: 0xd5dbe6, onFold: 0x1a2233,
        chips: neonChips, card: (Color.white, Color(hex: 0x16181d), Color(hex: 0xd63b3b), fourColorBlue, fourColorGreen, nil))

    static let neonDark = Theme(
        room: [0x141b29, 0x090c12, 0x020304], surface: [0x252c3c, 0x12151e, 0x090b10],
        rail: Rail(fill: .linear([Color(hex: 0x252b3a), Color(hex: 0x0c0e14)]), edge: Color(hex: 0x38e1b0),
                   glow: Color(hex: 0x38e1b0).opacity(0.65), grain: false),
        cushion: 0x05070a,
        line: Color(hex: 0x38e1b0).opacity(0.45), seat: Color(hex: 0x04060a), seatBorder: Color(hex: 0x38e1b0).opacity(0.25),
        seatText: 0xe8eaf0, text: 0xe8eaf0, onTable: 0xe8eaf0,
        accent: Color(hex: 0x38e1b0), onAccent: Color(hex: 0x06110d), fold: 0x2a2e3a,
        chips: neonChips, card: (Color(hex: 0x232a3a), Color(hex: 0xf1f3f8), Color(hex: 0xff6b6b), Color(hex: 0x6aa5ff), Color(hex: 0x4cc47a),
               Color(hex: 0x3a3f4d)))

    static let rubyLight = Theme(
        room: [0xdcc8ad, 0xbfa684, 0xa08764], surface: [0xee6f6a, 0xd04a4a, 0xb23638], rail: .leather, cushion: 0xb23638,
        line: gold.opacity(0.75), seat: Color(hex: 0xfffcf6), seatBorder: Color(hex: 0x782828).opacity(0.25),
        seatText: 0x3a1c1c, text: 0x3a1c1c, onTable: 0x3a1c1c, lightSeat: true, mutedOpacity: 0.9,
        accent: gold, onAccent: goldInk, formTint: Color(hex: 0x3a1c1c), fold: 0x8e2f2a)

    static let rubyDark = Theme(
        room: [0x2a2c32, 0x131416, 0x040405], surface: [0xa83236, 0x651519, 0x3a0a0e], rail: .leather, cushion: 0x2a070a,
        line: gold.opacity(0.75), seat: Color(hex: 0x080304), seatBorder: gold.opacity(0.3),
        seatText: 0xf3efe4, text: 0xf3efe6, onTable: 0xf6f1e4,
        accent: gold, onAccent: goldInk, fold: 0x3c3f46)

    static let royalLight = Theme(
        room: [0xb9c9e1, 0x8ea5c7, 0x6b85ac], surface: [0x86b6f7, 0x5b93e6, 0x3f78cf],
        rail: .chrome([0x9aa0aa, 0xe9ecf0, 0x888e98, 0xf4f6f8, 0x9298a2, 0xdde0e5]), cushion: 0xb3243a, cushionWidth: 0.025,
        line: Color(hex: 0xf5d682).opacity(0.9), seat: Color.white, seatBorder: Color(hex: 0x14234a).opacity(0.2),
        seatText: 0x14234a, text: 0x14234a, onTable: 0x14234a, lightSeat: true, mutedOpacity: 0.9,
        accent: Color(hex: 0x1f4e9c), onAccent: .white, formTint: Color(hex: 0x14234a), fold: 0xc0483a, chips: royalChips)

    static let royalDark = Theme(
        room: [0x232a3c, 0x0f131c, 0x030407], surface: [0x2f69c4, 0x163c7c, 0x0b2149],
        rail: .chrome([0x5d626b, 0xb9bdc4, 0x4e535b, 0xc6cad0, 0x585d66, 0xa9adb5]), cushion: 0x8e1b2e, cushionWidth: 0.025,
        line: gold.opacity(0.7), seat: Color(hex: 0x030710), seatBorder: Color.white.opacity(0.22),
        seatText: 0xf3efe4, text: 0xeef1f8, onTable: 0xf6f1e4,
        accent: Color(hex: 0xf2f4f7), onAccent: Color(hex: 0x14234a), fold: 0x6a2530, chips: royalChips)
}
