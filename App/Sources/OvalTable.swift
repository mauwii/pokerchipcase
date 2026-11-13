import PokerCore
import SwiftUI

/// How a seat is drawn while the player running the hand picks showdown winners.
enum SeatMark { case normal, selectable, selected, dimmed }

private let seatWidth: CGFloat = 70
private let seatHeight: CGFloat = 34

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
                        bet(seat.roundBet).position(toward(point, 0.5, in: size))
                    }
                    if seat.id == state.dealerID {
                        // A quarter step clockwise from the seat, so it clears the bet and the label.
                        let beside = seatPoint(index: i * 4 + 1, count: seats.count * 4, in: size)
                        dealerDisk.position(toward(beside, 0.75, in: size))
                    }
                    seatLabel(seat).position(point)
                }
            }
        }
    }

    private func seatLabel(_ seat: Seat) -> some View {
        let mark = seatState(seat)
        let acting = state.toActIndex.map { state.seats[$0].id } == seat.id
        let delta = seat.stack - seat.stackAtHandStart
        return VStack(spacing: 1) {
            Text(seat.name).fontWeight(seat.id == viewer ? .heavy : .regular).lineLimit(1)
            HStack(spacing: 3) {
                Text("\(seat.stack)").monospacedDigit().bold()
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
            RoundedRectangle(cornerRadius: 8).strokeBorder(
                acting || mark == .selected ? theme.accent : mark == .selectable ? theme.muted : .clear,
                lineWidth: acting || mark == .selected ? 2 : 1)
        }
        .opacity(mark == .dimmed ? 0.3 : seat.folded ? 0.4 : 1)
        .contentShape(.rect)
        .onTapGesture { if mark != .dimmed { onTapSeat?(seat.id) } }
        .allowsHitTesting(onTapSeat != nil)
    }

    private var pot: some View {
        VStack(spacing: 2) {
            if state.potTotal > 0 { chips(3) }
            Text("Pot \(state.potTotal)").font(.headline).monospacedDigit()
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
        HStack(spacing: 2) { chips(1); Text("\(amount)").monospacedDigit() }.font(.caption2.bold())
    }

    private var dealerDisk: some View {
        Text("D").font(.system(size: 9, weight: .black)).foregroundStyle(.black)
            .frame(width: 15, height: 15).background(.white, in: .circle)
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
