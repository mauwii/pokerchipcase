import PokerCore
import SwiftUI

/// How a seat is drawn while the player running the hand picks showdown winners.
enum SeatMark { case normal, selectable, selected, dimmed }

/// Seat labels scale with the table, so the seating looks the same on every phone:
/// about 80 points on a 375-point table, which keeps 10 seats apart.
private func seatWidth(in size: CGSize) -> CGFloat { min(size.width, size.height) * 0.215 }

/// Index 0 sits at the bottom center, the others follow clockwise on screen.
/// One radius for every seat, so the seating looks the same on every phone.
/// It leaves room for a seat label at every point, so labels never leave `size`.
func seatPoint(index: Int, count: Int, in size: CGSize) -> CGPoint {
    let angle = Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1))
    let r = min(size.width, size.height) / 2 - seatWidth(in: size) / 2
    return CGPoint(x: size.width / 2 + r * cos(angle), y: size.height / 2 + r * sin(angle))
}

/// The point `fraction` of the way from the center to `point`.
private func toward(_ point: CGPoint, _ fraction: CGFloat, in size: CGSize) -> CGPoint {
    CGPoint(x: size.width / 2 + (point.x - size.width / 2) * fraction,
            y: size.height / 2 + (point.y - size.height / 2) * fraction)
}

struct RoundTable: View {
    let state: GameState
    let viewer: PlayerID?
    var seatState: (Seat) -> SeatMark = { _ in .normal }
    var onTapSeat: ((PlayerID) -> Void)?
    @Environment(\.theme) private var theme
    /// Points kept for the rest of the screen. Read here, outside the size cap below, so it follows the
    /// text size the header, stack block and action bar are drawn at.
    @ScaledMetric private var reserve: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let seats = state.tableOrder(viewer: viewer)
            ZStack {
                TableSurface().padding(seatWidth(in: size) / 2 - 8)
                if state.config.digitalCards {
                    // The board sits just above the center. The pot, or after the payout the winning hands and
                    // the winners, hang below it as an overlay: they move with the board and can never cover it.
                    board(cardWidth: size.width * 0.085)
                        .overlay(alignment: .bottom) {
                            // Narrower than the gap between the side labels, so a long line shrinks or truncates instead of covering them.
                            Group { if handWinners.isEmpty { pot } else { winnerLines } }
                                .frame(width: size.width * 0.5).fixedSize(horizontal: false, vertical: true)
                                .alignmentGuide(.bottom) { $0[.top] - 8 }
                        }
                        .position(x: size.width / 2, y: size.height * 0.46)
                } else {
                    pot.position(x: size.width / 2, y: size.height / 2)
                }
                ForEach(Array(seats.enumerated()), id: \.element.id) { i, seat in
                    let point = seatPoint(index: i, count: seats.count, in: size)
                    // Only while betting: at showdown the bets are already counted in the pot.
                    // Digital games show the bet in the seat label: here it would cover the board.
                    if !state.config.digitalCards, state.phase == .betting, seat.roundBet > 0 {
                        // Halfway: further out, a bet next to a side seat overlaps its label.
                        let at = toward(point, 0.5, in: size)
                        // When the betting round ends, the bet slides into the pot.
                        // ponytail: no pot-to-winner animation yet; add it once the rest feels right.
                        bet(seat.roundBet).foregroundStyle(theme.onTable).onTableShadow(theme.onTableShadow).position(at).transition(.asymmetric(
                            insertion: .opacity,
                            removal: .offset(x: size.width / 2 - at.x, y: size.height / 2 - at.y).combined(with: .opacity)))
                    }
                    seatLabel(seat, width: seatWidth(in: size)).position(point)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: state.version)
        }
        .aspectRatio(1, contentMode: .fit)
        // From the screen height, not the space left over: that changes with the phase and
        // the dealer hint, and the table would grow and shrink with it. `reserve` stays for the
        // rest of the screen, 300 points at the default text size and more at larger ones; on an
        // iPhone SE the stack number shrinks while the dealer banner shows, so the table keeps its
        // size. Taller phones give everything above those points to the table, up to the screen width.
        .containerRelativeFrame(.vertical) { height, _ in max(height * 0.43, height - reserve) }
        // The layout constants assume at most this size; larger text would overlap the seats.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func seatLabel(_ seat: Seat, width: CGFloat) -> some View {
        let mark = seatState(seat)
        // Drawn like a picked winner, without the check mark.
        let look = wonWithHand(seat) ? SeatMark.selected : mark
        let acting = state.toActIndex.map { state.seats[$0].id } == seat.id
        let delta = seat.stack - seat.stackAtHandStart
        let showsDelta = state.phase == .handComplete && delta != 0
        let deltaText = Text(delta > 0 ? "+\(delta)" : "−\(-delta)").foregroundStyle(delta > 0 ? theme.green : theme.red)
        return VStack(spacing: 1) {
            HStack(spacing: 3) {
                // Inside the label, so it can never collide with a neighbour, a bet or the pot.
                if seat.id == state.dealerID { dealerDisk }
                Text(seat.name).fontWeight(seat.id == viewer ? .heavy : .regular).lineLimit(1)
                    .accessibilityIdentifier("seatName")
            }
            HStack(spacing: 3) {
                // One Text, so stack, delta and check mark shrink together instead of wrapping one by one.
                // At hand end the delta stands in for the stack, so "+5.040" is never cut to "…";
                // the next hand shows the stack again.
                ((showsDelta ? deltaText : Text("\(seat.stack)")).monospacedDigit()
                    + Text(mark == .selected ? " ✓" : ""))
                    .bold().contentTransition(.numericText())
                    .accessibilityIdentifier(showsDelta ? "seatDelta" : "seatStack")
                // The hand is over, and the tag would squeeze the delta.
                if seat.allIn, state.phase != .handComplete { tag("All-in") }
            }
            // One extra row at most: the bet while betting, the cards from the showdown on.
            if state.config.digitalCards, state.phase == .betting, seat.roundBet > 0 {
                bet(seat.roundBet)
            } else if revealed(seat) {
                CardsText(cards: seat.holeCards).font(.caption2).accessibilityIdentifier("seatCards")
            }
        }
        .font(.footnote)
        .foregroundStyle(theme.seatText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .frame(maxWidth: width)
        .background(theme.seat, in: .rect(cornerRadius: 8))
        // Glowing rails get a glowing ring; below the opaque fill, so only the outside of the glow shows and no text sits on it.
        .background {
            if acting, theme.rail.glow != nil {
                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent, lineWidth: 2)
                    .phaseAnimator([1.0, 0.4]) { ring, opacity in ring.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
                    .shadow(color: theme.accent, radius: 4)
            }
        }
        .overlay {
            if acting {
                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent, lineWidth: 2)
                    .phaseAnimator([1.0, 0.4]) { ring, opacity in ring.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
            } else {
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    borderColor(look),
                    lineWidth: look == .selected ? 2 : 1)
            }
        }
        .opacity(seatOpacity(mark, folded: seat.folded))
        .contentShape(.rect)
        .onTapGesture { if mark != .dimmed { onTapSeat?(seat.id) } }
        .allowsHitTesting(onTapSeat != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTapSeat != nil && mark != .dimmed ? .isButton : [])
        .accessibilityAddTraits(mark == .selected ? .isSelected : [])
    }

    /// The seat's cards are on the table for everyone; only digital games have cards.
    private func revealed(_ seat: Seat) -> Bool { state.config.digitalCards && state.isRevealed(seat) }

    // ponytail: a winner is a revealed seat that gained chips or holds the best revealed hand (the main-pot winner always does, which covers chops); a side-pot winner with a lesser hand who still lost chips overall is not marked, keep the winners in GameState if that matters
    private func wonWithHand(_ seat: Seat) -> Bool {
        guard state.phase == .handComplete, revealed(seat) else { return false }
        if seat.stack > seat.stackAtHandStart { return true }
        let best = state.seats.filter(revealed).compactMap { state.handValue(of: $0) }.max()
        return best != nil && state.handValue(of: seat) == best
    }

    /// Five places, so the row does not jump while the cards are dealt.
    private func board(cardWidth: CGFloat) -> some View {
        HStack(spacing: cardWidth * 0.15) {
            ForEach(0..<5, id: \.self) { i in
                ZStack {
                    CardSlotView(width: cardWidth)
                    if i < state.board.count { CardFaceView(card: state.board[i], width: cardWidth).transition(.opacity) }
                }
            }
        }
    }

    /// Revealed seats that won the hand (chips gained or best hand, so chops count), with their hands, in seat order.
    private var handWinners: [(Seat, HandValue)] {
        state.seats.filter(wonWithHand).compactMap { seat in state.handValue(of: seat).map { (seat, $0) } }
    }

    /// After the payout: the winning hands, then the winners, where the empty pot was.
    private var winnerLines: some View {
        let winners = handWinners
        // Each hand once, e.g. "Flush · Two pair" when a side pot went to another hand.
        let hands = winners.map(\.1.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(spacing: 2) {
            Text(hands.joined(separator: " · ")).font(.caption).accessibilityIdentifier("winningHands")
            Text(winners.map(\.0.name).joined(separator: ", ")).font(.caption.bold()).accessibilityIdentifier("winners")
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(theme.seatText)
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(theme.seat, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.seatBorder, lineWidth: 1))
    }

    private var pot: some View {
        VStack(spacing: 2) {
            // Nothing at hand end: "Pot 0" next to the paid-out stacks reads like an error.
            if state.potTotal > 0 {
                chips(3)
                Text("Pot \(state.potTotal)").font(.headline).monospacedDigit().contentTransition(.numericText())
                    // A plate in every theme: dark ink on Rubin's red felt still fails the audit (3.49 at the edge).
                    .foregroundStyle(theme.seatText)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(theme.seat, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.seatBorder, lineWidth: 1))
                    .accessibilityIdentifier("pot")
            }
            if state.pots.count > 1 {
                Text(state.pots.indices.map { potName($0, of: state.pots.count) + " " + state.pots[$0].amount.formatted() }.joined(separator: " · "))
                    // Full onTable, not theme.muted (tuned for the room) or a faded one: light felts leave no room for less.
                    .font(.caption2)
            }
        }
        .foregroundStyle(theme.onTable)
        .onTableShadow(theme.onTableShadow)
    }

    private func borderColor(_ mark: SeatMark) -> Color {
        switch mark {
        case .selected: theme.accent
        case .selectable: theme.muted
        case .normal, .dimmed: theme.seatBorder
        }
    }

    private func seatOpacity(_ mark: SeatMark, folded: Bool) -> Double {
        if mark == .dimmed { 0.3 } else if folded { 0.4 } else { 1 }
    }

    private func bet(_ amount: Chips) -> some View {
        HStack(spacing: 2) {
            chips(1)
            Text("\(amount)").monospacedDigit().contentTransition(.numericText()).accessibilityIdentifier("seatBet")
        }
            .font(.caption2.bold())
    }

    private var dealerDisk: some View {
        Text("D").font(.system(size: 8, weight: .black)).foregroundStyle(.black)
            .frame(width: 12, height: 12).background(.white, in: .circle)
            .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel("Dealer")
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 8, weight: .heavy)).foregroundStyle(theme.onAccent)
            .padding(.horizontal, 3).background(theme.accent, in: .rect(cornerRadius: 3))
    }

    // ponytail: decorative chips only, no breakdown into chip values; value-accurate stacks if someone asks.
    private func chips(_ count: Int) -> some View {
        HStack(spacing: -4) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(theme.chips[i % theme.chips.count])
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [2.5, 2])))
                    .frame(width: 12, height: 12)
            }
        }
    }
}

private extension View {
    /// A soft dark shadow under light text on a light felt, where the theme asks for it.
    @ViewBuilder func onTableShadow(_ on: Bool) -> some View {
        if on { shadow(color: .black.opacity(0.35), radius: 1) } else { self }
    }
}

/// The display name of pot `index` among `count` pots: "Main", then "Side" or "Side 1", "Side 2", ….
func potName(_ index: Int, of count: Int) -> String {
    if index == 0 { "Main" } else if count == 2 { "Side" } else { "Side \(index)" }
}
