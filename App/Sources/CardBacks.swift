import SwiftUI

/// Gold of the monogram back's letter and frame, the same for every back color and theme.
private let monogramGold = Color(hex: 0xe8c15a)

/// A face-down card in a back color and pattern. Sizes are fractions of the card width, from the approved mockup.
struct CardBackView: View {
    let back: CardBack
    let width: CGFloat
    /// Draws this pattern instead of the stored one, e.g. in a settings picker.
    var pattern: CardBackPattern?
    @AppStorage("cardBackPattern") private var storedPattern = CardBackPattern.medallion
    @AppStorage("playerName") private var playerName = ""
    @Environment(\.theme) private var theme

    var body: some View {
        let pattern = pattern ?? storedPattern
        let inner = RoundedRectangle(cornerRadius: width * 0.08)
        back.color
            .overlay {
                drawing(pattern)
                    .clipShape(inner)
                    .overlay(inner.strokeBorder(pattern == .monogram ? monogramGold : theme.cardFrame, lineWidth: line * 1.5))
                    .padding(width * 0.08)
            }
            .modifier(CardShape(width: width))
            .cardShadow(width: width)
            .accessibilityHidden(true)
    }

    private var line: CGFloat { max(0.5, width * 0.012) }

    @ViewBuilder private func drawing(_ pattern: CardBackPattern) -> some View {
        switch pattern {
        case .lattice:
            lattice(step: max(2, width * 0.09), opacity: 0.35)
        case .medallion:
            lattice(step: max(2, width * 0.06), opacity: 0.16)
                .overlay {
                    Circle().stroke(.white.opacity(0.9), lineWidth: max(0.5, width * 0.014)).frame(width: width * 0.33)
                    Circle().stroke(.white.opacity(0.5), lineWidth: max(0.5, width * 0.011)).frame(width: width * 0.44)
                    Text("♠").font(.system(size: width * 0.32)).foregroundStyle(.white)
                }
        case .rays:
            Canvas { context, size in
                // 30 wedges of 6°, 6° apart, reaching past the corners.
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = hypot(size.width, size.height)
                var path = Path()
                for i in 0..<30 {
                    let start = Angle.degrees(Double(i) * 12)
                    path.move(to: center)
                    path.addArc(center: center, radius: radius, startAngle: start, endAngle: start + .degrees(6), clockwise: false)
                    path.closeSubpath()
                }
                context.fill(path, with: .color(.white.opacity(0.3)))
            }
            .overlay {
                Circle().fill(back.color).frame(width: width * 0.26)
                    .overlay(Circle().strokeBorder(.white, lineWidth: max(0.5, width * 0.02)))
            }
        case .stripes:
            Canvas { context, size in
                // Stripes across an axis 60° clockwise from up, i.e. lines falling 60° to the right.
                let reach = hypot(size.width, size.height)
                let period = max(3, width * 0.12)
                context.translateBy(x: size.width / 2, y: size.height / 2)
                context.rotate(by: .degrees(-30))
                var path = Path()
                var x = -reach
                while x < reach {
                    path.addRect(CGRect(x: x, y: -reach, width: period * 0.4, height: reach * 2))
                    x += period
                }
                context.fill(path, with: .color(.white.opacity(0.3)))
            }
        case .dots:
            Canvas { context, size in
                // Two square grids, the second offset by half a step both ways.
                let step = max(3, width * 0.107)
                let r = max(0.5, width * 0.021)
                var path = Path()
                var row = 0
                var y: CGFloat = 0
                while y < size.height + step {
                    var x: CGFloat = row.isMultiple(of: 2) ? 0 : step / 2
                    while x < size.width + step {
                        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                        x += step
                    }
                    y += step / 2
                    row += 1
                }
                context.fill(path, with: .color(.white.opacity(0.55)))
            }
        case .monogram:
            LinearGradient(stops: [.init(color: .white.opacity(0.28), location: 0), .init(color: .clear, location: 0.45),
                                   .init(color: .black.opacity(0.25), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    // Drawn, not a Text: decoration, which the contrast audit would judge as text (#151).
                    Canvas { context, size in
                        let letter = Text(CardBackPattern.monogram(playerName) ?? "♠")
                            .font(.system(size: width * 0.5, weight: .bold, design: .serif))
                            .foregroundColor(monogramGold)
                        context.draw(letter, at: CGPoint(x: size.width / 2, y: size.height / 2))
                    }
                }
        }
    }

    /// Two sets of diagonals at a fixed step form a diamond lattice.
    private func lattice(step: CGFloat, opacity: Double) -> some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: line)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 10) {
            ForEach(CardBackPattern.allCases, id: \.self) { pattern in
                HStack {
                    ForEach(CardBack.allCases, id: \.self) { CardBackView(back: $0, width: 50, pattern: pattern) }
                }
            }
        }
        .padding()
    }
    .background(ThemeName.felt.palette(for: .light).surface[0])
}
