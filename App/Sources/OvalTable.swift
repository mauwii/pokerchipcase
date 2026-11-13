import PokerCore
import SwiftUI

/// How a seat is drawn while the player running the hand picks showdown winners.
enum SeatMark { case normal, selectable, selected, dimmed }

private let seatWidth: CGFloat = 70
private let seatHeight: CGFloat = 38

/// Index 0 sits at the bottom center, the others follow clockwise on screen.
/// The radii leave room for a seat label at every point, so labels never leave `size`.
func seatPoint(index: Int, count: Int, in size: CGSize) -> CGPoint {
    let angle = Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1))
    let rx = size.width / 2 - seatWidth / 2, ry = size.height / 2 - seatHeight / 2
    return CGPoint(x: size.width / 2 + rx * cos(angle), y: size.height / 2 + ry * sin(angle))
}

/// The point `fraction` of the way from the center to `point`.
private func toward(_ point: CGPoint, _ fraction: CGFloat, in size: CGSize) -> CGPoint {
    CGPoint(x: size.width / 2 + (point.x - size.width / 2) * fraction,
            y: size.height / 2 + (point.y - size.height / 2) * fraction)
}

struct OvalTable: View {
    let state: GameState
    let viewer: PlayerID?
    var seatState: (Seat) -> SeatMark = { _ in .normal }
    var onTapSeat: ((PlayerID) -> Void)?
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let seats = state.tableOrder(viewer: viewer)
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: theme.surface, center: .center, startRadius: 0, endRadius: size.width / 2))
                    .overlay(Ellipse().strokeBorder(theme.rim, lineWidth: 7))
                    .padding(.horizontal, seatWidth / 2 - 8)
                    .padding(.vertical, seatHeight / 2 - 6)
                pot.position(x: size.width / 2, y: size.height / 2)
                ForEach(Array(seats.enumerated()), id: \.element.id) { i, seat in
                    let point = seatPoint(index: i, count: seats.count, in: size)
                    if seat.roundBet > 0 {
                        // Halfway: further out, a bet next to a side seat overlaps its label.
                        let at = toward(point, 0.5, in: size)
                        // When the betting round ends, the bet slides into the pot.
                        // ponytail: no pot-to-winner animation yet; add it once the rest feels right.
                        bet(seat.roundBet).position(at).transition(.asymmetric(
                            insertion: .opacity,
                            removal: .offset(x: size.width / 2 - at.x, y: size.height / 2 - at.y).combined(with: .opacity)))
                    }
                    seatLabel(seat).position(point)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: state.version)
        }
        // The layout constants assume at most this size; larger text would overlap the seats.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func seatLabel(_ seat: Seat) -> some View {
        let mark = seatState(seat)
        let acting = state.toActIndex.map { state.seats[$0].id } == seat.id
        let delta = seat.stack - seat.stackAtHandStart
        return VStack(spacing: 1) {
            HStack(spacing: 3) {
                // Inside the label, so it can never collide with a neighbour, a bet or the pot.
                if seat.id == state.dealerID { dealerDisk }
                Text(seat.name).fontWeight(seat.id == viewer ? .heavy : .regular).lineLimit(1)
            }
            HStack(spacing: 3) {
                Text("\(seat.stack)").monospacedDigit().bold().contentTransition(.numericText())
                if seat.allIn { tag("All-in") }
                if state.phase == .handComplete, delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "−\(-delta)").foregroundStyle(delta > 0 ? .green : .red).bold()
                }
                if mark == .selected { Text("✓").bold() }
            }
        }
        .font(.caption)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .frame(maxWidth: seatWidth)
        .background(mark == .selected ? theme.accent.opacity(0.35) : theme.seat, in: .rect(cornerRadius: 8))
        .overlay {
            if acting {
                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent, lineWidth: 2)
                    .phaseAnimator([1.0, 0.4]) { ring, opacity in ring.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
            } else {
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    mark == .selected ? theme.accent : mark == .selectable ? theme.muted : .clear,
                    lineWidth: mark == .selected ? 2 : 1)
            }
        }
        .opacity(mark == .dimmed ? 0.3 : seat.folded ? 0.4 : 1)
        .contentShape(.rect)
        .onTapGesture { if mark != .dimmed { onTapSeat?(seat.id) } }
        .allowsHitTesting(onTapSeat != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTapSeat != nil && mark != .dimmed ? .isButton : [])
        .accessibilityAddTraits(mark == .selected ? .isSelected : [])
    }

    private var pot: some View {
        VStack(spacing: 2) {
            if state.potTotal > 0 { chips(3) }
            Text("Pot \(state.potTotal)").font(.headline).monospacedDigit().contentTransition(.numericText())
            if state.pots.count > 1 {
                Text(state.pots.indices.map { potName($0) + " \(state.pots[$0].amount)" }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(theme.muted)
            }
        }
    }

    private func potName(_ i: Int) -> String {
        i == 0 ? "Main" : state.pots.count == 2 ? "Side" : "Side \(i)"
    }

    private func bet(_ amount: Chips) -> some View {
        HStack(spacing: 2) { chips(1); Text("\(amount)").monospacedDigit().contentTransition(.numericText()) }
            .font(.caption2.bold())
    }

    private var dealerDisk: some View {
        Text("D").font(.system(size: 8, weight: .black)).foregroundStyle(.black)
            .frame(width: 12, height: 12).background(.white, in: .circle)
            .accessibilityLabel("Dealer")
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 8, weight: .heavy)).foregroundStyle(theme.background)
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
