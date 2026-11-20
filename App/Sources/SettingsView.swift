import PokerCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var themeName = ThemeName.felt
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("cardBack") private var cardBack = CardBack.red
    @AppStorage("cardBackPattern") private var cardBackPattern = CardBackPattern.medallion
    @AppStorage("cardFace") private var cardFace = CardFace.classic
    @AppStorage("fourColorDeck") private var fourColorDeck = false
    @Environment(\.theme) private var theme
    @Environment(\.stageScheme) private var stageScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $themeName) {
                        ForEach(ThemeName.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Brightness", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .themedRow()

                Section {
                    // Reads the stored choices, so it follows every row below.
                    HStack(spacing: 12) {
                        ForEach(["As", "Td"].compactMap(Card.init), id: \.self) { CardFaceView(card: $0, width: 44) }
                        CardBackView(back: cardBack, width: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)
                    Picker("Card face", selection: $cardFace) {
                        ForEach(CardFace.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle(isOn: $fourColorDeck) { Text("Four-color deck").accessibilityIdentifier("fourColorDeck") }
                    Picker(selection: $cardBackPattern) {
                        ForEach(CardBackPattern.allCases, id: \.self) { Text($0.label).tag($0) }
                    } label: {
                        Text("Back pattern").accessibilityIdentifier("backPattern")
                    }
                } header: {
                    Text("Cards").foregroundStyle(theme.muted)
                }
                .themedRow()

                Section {
                    Picker("Back color", selection: $cardBack) {
                        ForEach(CardBack.allCases, id: \.self) { back in
                            // Not a Label: the audit judges a Label's icon with its text, and the red back fails on a dark row.
                            HStack(spacing: 17) {
                                CardBackView(back: back, width: 22)
                                Text(back.label)
                            }
                            .tag(back)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Back color").foregroundStyle(theme.muted).accessibilityIdentifier("backColorHeader")
                }
                .themedRow()
            }
            // A menu picker keeps its old tint when the palette flips under the open sheet; rebuild it with the new one.
            .id(theme.formTint)
            .navigationTitle("Settings")
            .toolbar {
                // Without the bar's glass, Done reads in formTint on the opaque screen: the audit fails text on
                // translucent glass whatever the pixels show (#143).
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .confirmationAction) { doneButton }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                }
            }
            .themedScreen()
        }
        // A sheet keeps the scheme it opened with; the root's preferredColorScheme does not reach it while it is open (#142).
        // Never nil: nil leaves the sheet in the scheme it had, so System passes the window's.
        .preferredColorScheme(appearance.colorScheme ?? stageScheme)
    }

    private var doneButton: some View {
        Button("Done") { dismiss() }.accessibilityIdentifier("settingsDone")
    }
}
