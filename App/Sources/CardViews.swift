import PokerCore
import SwiftUI

extension Card {
    var symbol: String {
        switch suit {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }

    var rankLabel: String {
        switch rank {
        case 11: "J"
        case 12: "Q"
        case 13: "K"
        case 14: "A"
        default: "\(rank)"
        }
    }

    /// For VoiceOver, e.g. "Ace of hearts".
    var spokenName: String {
        let rankName =
            switch rank {
            case 11: "Jack"
            case 12: "Queen"
            case 13: "King"
            case 14: "Ace"
            default: "\(rank)"
            }
        let suitName =
            switch suit {
            case .clubs: "clubs"
            case .diamonds: "diamonds"
            case .hearts: "hearts"
            case .spades: "spades"
            }
        return "\(rankName) of \(suitName)"
    }
}

extension [Card] {
    var spokenNames: String { map(\.spokenName).joined(separator: ", ") }
}

/// Card size and shape shared by face, back and slot: 5:7, corners at 12 % of the width.
struct CardShape: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content.frame(width: width, height: width * 1.4).clipShape(.rect(cornerRadius: width * 0.12))
    }
}

extension View {
    /// Soft drop shadow under a face or back; goes after `CardShape`, whose clip would cut it off.
    func cardShadow(width: CGFloat) -> some View {
        shadow(color: .black.opacity(0.45), radius: width * 0.04, y: width * 0.03)
    }
}

struct CardFaceView: View {
    let card: Card
    let width: CGFloat
    /// Draws this face instead of the stored one, e.g. in a settings picker.
    var face: CardFace?
    @AppStorage("cardFace") private var storedFace = CardFace.classic
    @AppStorage("fourColorDeck") private var fourColor = false
    @Environment(\.theme) private var theme

    var body: some View {
        layout(face ?? storedFace)
            .frame(width: width, height: width * 1.4)
            .overlay {
                if let edge = theme.cardEdge {
                    RoundedRectangle(cornerRadius: width * 0.12).strokeBorder(edge, lineWidth: max(1, width * 0.03))
                }
            }
            .modifier(CardShape(width: width))
            .cardShadow(width: width)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.spokenName)
    }

    /// Glyph sizes and insets as fractions of the card's width (`left`, `right`) and height (`top`, `bottom`),
    /// measured from the approved mockup. Negative insets let the big suit run off the card.
    private struct Metrics {
        var rank: CGFloat
        var tracking: CGFloat
        var top: CGFloat
        var left: CGFloat
        var small: CGFloat?
        var big: CGFloat
        var right: CGFloat
        var bottom: CGFloat
        var bigOpacity: Double = 1
    }

    @ViewBuilder private func layout(_ face: CardFace) -> some View {
        let ink = theme.suitColor(card.suit, fourColor: fourColor)
        switch face {
        case .centered:
            VStack(spacing: 0) {
                glyph(card.rankLabel, size: width * 0.42)
                glyph(card.symbol, size: width * 0.42)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.cardFace)
        case .classic:
            indexed(Metrics(rank: 0.34, tracking: -0.06, top: 0.06, left: 0.09, small: 0.24, big: 0.62, right: 0.08, bottom: 0.06))
                .foregroundStyle(ink).background(theme.cardFace)
        case .jumbo:
            indexed(Metrics(rank: 0.56, tracking: -0.07, top: 0.05, left: 0.08, small: nil, big: 0.58, right: 0.06, bottom: 0.04))
                .foregroundStyle(ink).background(theme.cardFace)
        case .solid:
            indexed(Metrics(rank: 0.52, tracking: -0.07, top: 0.06, left: 0.09, small: nil, big: 0.95, right: -0.06, bottom: -0.08,
                            bigOpacity: 0.28))
                .foregroundStyle(.white).background(solidFill)
        }
    }

    /// Rank (and small suit) as an index top left, one big suit bottom right.
    private func indexed(_ m: Metrics) -> some View {
        let height = width * 1.4
        return ZStack {
            VStack(spacing: 0) {
                glyph(card.rankLabel, size: width * m.rank, tracking: m.tracking)
                if let small = m.small { glyph(card.symbol, size: width * small) }
            }
            .padding(.top, height * m.top).padding(.leading, width * m.left)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if m.bigOpacity < 1 {
                // Drawn, not a Text: decoration, which the contrast audit would judge as text (#151).
                Canvas { context, size in
                    let suit = Text(card.symbol).font(.system(size: width * m.big, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(m.bigOpacity))
                    context.draw(suit, at: CGPoint(x: size.width - width * m.right, y: size.height - height * m.bottom),
                                 anchor: .bottomTrailing)
                }
            } else {
                glyph(card.symbol, size: width * m.big)
                    .padding(.trailing, width * m.right).padding(.bottom, height * m.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private func glyph(_ text: String, size: CGFloat, tracking: CGFloat = 0) -> some View {
        Text(text).font(.system(size: size, weight: .bold, design: .rounded)).tracking(size * tracking)
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityIdentifier("cardGlyph")
    }

    /// The `solid` face's ground: fixed per suit in every theme. Without the four-color deck, diamonds take
    /// the hearts fill and clubs the spades fill.
    private var solidFill: LinearGradient {
        let spades: (UInt32, UInt32) = (0x3a3f4b, 0x16181d)
        let hearts: (UInt32, UInt32) = (0xd53524, 0xa82a1f)
        let stops =
            switch card.suit {
            case .spades: spades
            case .hearts: hearts
            case .diamonds: fourColor ? (0x2470d3, 0x1f4e9c) : hearts
            case .clubs: fourColor ? (0x2e814e, 0x1b6f3c) : spades
            }
        // CSS 160°: down and slightly to the right.
        return LinearGradient(colors: [Color(hex: stops.0), Color(hex: stops.1)],
                              startPoint: UnitPoint(x: 0.32, y: 0), endPoint: UnitPoint(x: 0.68, y: 1))
    }
}

/// Where a card will lie, e.g. a board card not dealt yet.
struct CardSlotView: View {
    let width: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .strokeBorder(theme.onTable.opacity(0.25), lineWidth: max(1, width * 0.03))
            .modifier(CardShape(width: width))
            .accessibilityHidden(true)
    }
}

/// Cards inline, e.g. `A♥ K♠`, with hearts and diamonds in the theme's red, or in four colors.
struct CardsText: View {
    let cards: [Card]
    @AppStorage("fourColorDeck") private var fourColor = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(attributed).accessibilityLabel(cards.spokenNames)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        // On a dark seat the cream card's inks reach about 3:1; Neon dark's card inks reach 6.5:1 or more (#134).
        let inks = scheme == .dark ? ThemeName.neon.palette(for: .dark) : theme
        for (index, card) in cards.enumerated() {
            if index > 0 { result += AttributedString(" ") }
            var part = AttributedString(card.rankLabel + card.symbol)
            // Spades, and clubs in the two-color deck, keep the surrounding text color.
            if card.suit == .hearts || card.suit == .diamonds || fourColor && card.suit == .clubs {
                part.foregroundColor = inks.suitColor(card.suit, fourColor: fourColor)
            }
            result += part
        }
        return result
    }
}

/// The own two hole cards: face down unless `faceUp`, shown while pressed, or through the "Show cards" action.
struct HoleCardsView: View {
    let cards: [Card]
    let faceUp: Bool
    let width: CGFloat
    @AppStorage("cardBack") private var back = CardBack.red
    @GestureState private var pressed = false
    @State private var revealed = false

    var body: some View {
        let shown = faceUp || pressed || revealed
        HStack(spacing: width * 0.1) {
            ForEach(cards, id: \.self) { card in
                if shown { CardFaceView(card: card, width: width) } else { CardBackView(back: back, width: width) }
            }
        }
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown ? cards.spokenNames : "Your cards, hidden")
        .accessibilityIdentifier("holeCards")
        .accessibilityActions {
            if !faceUp {
                Button(revealed ? "Hide cards" : "Show cards") {
                    revealed.toggle()
                    if revealed { AccessibilityNotification.Announcement(cards.spokenNames).post() }
                }
            }
        }
        .onChange(of: cards) { revealed = false }
    }
}

#Preview {
    let cards = ["As", "Td", "Kh", "Qc"].compactMap(Card.init)
    VStack(spacing: 0) {
        ForEach([("Felt light", ThemeName.felt.palette(for: .light)), ("Neon dark", ThemeName.neon.palette(for: .dark))], id: \.0) { _, theme in
            VStack(spacing: 8) {
                ForEach(CardFace.allCases, id: \.self) { face in
                    HStack {
                        ForEach(cards, id: \.self) { CardFaceView(card: $0, width: 32, face: face) }
                        CardSlotView(width: 32)
                    }
                }
                CardsText(cards: cards).foregroundStyle(theme.text)
                HoleCardsView(cards: Array(cards.prefix(2)), faceUp: false, width: 50)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface[0])
            .environment(\.theme, theme)
        }
    }
}
