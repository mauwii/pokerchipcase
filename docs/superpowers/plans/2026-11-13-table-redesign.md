# Table Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An oval poker table on the table screen, plus a per-device "Felt / Dark / System" appearance setting with two themes.

**Architecture:** A `Theme` value in the SwiftUI environment, derived from `colorScheme`, which the app root forces through `preferredColorScheme` from `@AppStorage("appearance")`. `TableView` becomes an oval table: one pure ordering helper in `PokerCore` (tested) plus ellipse placement in the app. The showdown winner selection moves out of `ShowdownView` into `TableView`, so the oval and the "Pay out" bar share it.

**Tech Stack:** Swift 6, SwiftUI (iOS 17), Swift Testing.

**Spec:** [2026-11-13-table-redesign.md](../specs/2026-11-13-table-redesign.md)

## Global Constraints

- Branch `feat/table-redesign` (exists, the spec is committed there).
- `PokerNet`, `PokerSession` and the wire protocol do not change. `PokerCore` gets exactly one new public read-only helper (Task 2), so `docs/PROTOCOL.md` stays as it is.
- No new dependencies. Deployment target stays iOS 17.0.
- Setting values: `@AppStorage("appearance")` stores `"felt"`, `"dark"` or `"system"`, and the default is `"system"`. Picker labels are exactly "Felt", "Dark", "System".
- UI copy is English, as today.
- Keep the two `ponytail:` notes from the spec as code comments: decorative chips (in `TableView`) and no pot-to-winner animation (in the animation code).
- The app has no unit tests. Each app task ends with the app build from AGENTS.md plus the manual check named in the task.
- App build command (from the repo root):
  `xcodegen generate --spec App/project.yml && xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet`
- Commits: Conventional Commits, scope `app` or `core`.

## Review Focus

1. Ten seats with long names on the iPhone SE (3rd generation): seat labels, bets, the D disk and the pot must not overlap. Expect truncated names and shrunken text, never overlap. → Task 3 manual check.
2. The viewer is eliminated or has no seat (`session.me == nil`, or a busted seat): the first remaining seat sits at the bottom and nothing crashes. → Task 2 test `tableOrderWithoutViewerStartsAtFirstRemainingSeat`, Task 3 manual check.
3. Showdown where the player running the hand is not eligible for a pot, or the pots change mid-selection: only eligible seats can be tapped, and the selection resets when `state.pots` changes. → Task 5 manual check.
4. Switching the appearance while a table is open, and with a sheet or alert showing: the table, the sheets and the alerts all follow at once. → Task 1 manual check, repeated in Task 7.
5. Heads-up (2 players): the two seats sit top and bottom, and the bets and the D disk stay clear of the pot. → Task 3 manual check.

---

### Task 1: Theme, appearance setting, settings screen

**Files:**

- Create: `App/Sources/Theme.swift`
- Create: `App/Sources/SettingsView.swift`
- Modify: `App/Sources/PokerChipCaseApp.swift`
- Modify: `App/Sources/StartView.swift` (gear button in the toolbar, settings sheet)

**Interfaces:**

- Produces:
  - `enum Appearance: String, CaseIterable { case felt, dark, system }` with `var label: String` ("Felt", "Dark", "System") and `var colorScheme: ColorScheme?` (`.light`, `.dark`, `nil`).
  - `struct Theme: Sendable` with the stored properties `background: Color`, `surface: [Color]` (inner and outer stop of a radial gradient, so the type stays `Sendable`; the view builds the `RadialGradient`), `rim: Color`, `accent: Color`, `seat: Color`, `text: Color`, `muted: Color`, `fold: Color`, `chips: [Color]` (exactly 3).
  - `static let felt: Theme` and `static let dark: Theme`, with these values from the mockups:
    - felt: background `#3b2414`, surface `[#2f8a4e, #1d5e33]`, rim `#6b3f1d`, accent `#e8c15a`, seat black at 45 % opacity, text `#f3e9d2`, muted `#c9b99a`, fold `#7a2a1f`, chips `#c0392b`, `#2c3e50`, `#27ae60`
    - dark: background `#0d0f14`, surface `[#171a22, #171a22]`, rim `#232733`, accent `#38e1b0`, seat `#232733`, text `#e8eaf0`, muted `#8a90a2`, fold `#2a2e3a`, chips `#38e1b0`, `#5b6cff`, `#ff9f68`
  - `extension EnvironmentValues { @Entry var theme: Theme = .felt }`
  - `extension View { func themed() -> some View }`: reads `@Environment(\.colorScheme)` in a private modifier, sets `.environment(\.theme, scheme == .dark ? .dark : .felt)` and `.tint(theme.accent)`.
  - `struct SettingsView: View`: a `Form` with a segmented `Picker("Appearance", …)` over `Appearance.allCases`, bound to `@AppStorage("appearance")`, with a "Done" button that dismisses.

- [ ] **Step 1:** Write `Theme.swift` with `Appearance`, `Theme`, the environment entry and `themed()`. Use one private `Color(hex:)` initializer in the same file.
- [ ] **Step 2:** In `PokerChipCaseApp`, add `@AppStorage("appearance") private var appearance = Appearance.system`. On the root `Group`, apply `.themed()` and then `.preferredColorScheme(appearance.colorScheme)`. The order matters: `themed()` must sit *inside* `preferredColorScheme`, so it sees the forced scheme.
- [ ] **Step 3:** Write `SettingsView.swift`. In `StartView`, add `@State private var showSettings = false`, a `ToolbarItem` with `Button("Settings", systemImage: "gearshape")`, and `.sheet(isPresented: $showSettings) { SettingsView() }`.
- [ ] **Step 4:** Run the app build. Expected: `** BUILD SUCCEEDED **`, or no output with `-quiet` and exit code 0.
- [ ] **Step 5: Manual check** in the simulator:
  - Each of the three options changes the start screen at once. "System" follows Settings → Display.
  - Open a table and switch the appearance through Control Center → Dark Mode while "System" is selected. The table screen follows.
- [ ] **Step 6: Commit** `feat(app): appearance setting with felt and dark themes`

### Task 2: Seat order around the table (PokerCore, TDD)

**Files:**

- Modify: `Sources/PokerCore/Hand.swift` (next to `potTotal`)
- Test: `Tests/PokerCoreTests/TableOrderTests.swift` (new)

**Interfaces:**

- Produces: `public func tableOrder(viewer: PlayerID?) -> [Seat]` on `GameState`. It returns the seats that are not eliminated, in seat order, rotated so that `viewer` comes first. If `viewer` is nil, eliminated or unknown, the order starts at the first remaining seat.

- [ ] **Step 1: Write the failing tests** in `TableOrderTests.swift`, using `Game.started` from `Helpers.swift`:

  ```swift
  @Test func tableOrderStartsAtViewer() throws {
      let g = try Game.started(["A": 1000, "B": 1000, "C": 1000, "D": 1000])
      #expect(g.state.tableOrder(viewer: "C").map(\.id) == ["C", "D", "A", "B"])
  }

  @Test func tableOrderSkipsEliminatedSeats() throws {
      var g = try Game.started(["A": 1000, "B": 300, "C": 1000])
      try g.act(.allIn); try g.act(.call); try g.act(.call)
      try g.apply(.resolveShowdown(winners: [["B"], ["C"]]), by: "A", at: t0)  // A is out (see HandEndTests)
      #expect(g.state.tableOrder(viewer: "B").map(\.id) == ["B", "C"])
  }

  @Test func tableOrderWithoutViewerStartsAtFirstRemainingSeat() throws {
      var g = try Game.started(["A": 1000, "B": 300, "C": 1000])
      try g.act(.allIn); try g.act(.call); try g.act(.call)
      try g.apply(.resolveShowdown(winners: [["B"], ["C"]]), by: "A", at: t0)
      #expect(g.state.tableOrder(viewer: nil).map(\.id) == ["B", "C"])
      #expect(g.state.tableOrder(viewer: "A").map(\.id) == ["B", "C"])
  }
  ```

- [ ] **Step 2:** Run `swift test --filter TableOrder`. Expected: compile error, `value of type 'GameState' has no member 'tableOrder'`.
- [ ] **Step 3:** Implement `tableOrder(viewer:)` in `Hand.swift`.
- [ ] **Step 4:** Run `swift test`. Expected: all tests pass, including the 3 new ones.
- [ ] **Step 5: Commit** `feat(core): seat order around the table for a viewer`

### Task 3: Oval table view

**Files:**

- Create: `App/Sources/OvalTable.swift`
- Modify: `App/Sources/TableView.swift` (replace the `List` and the pot/stack block, and apply the theme to the screen)

**Interfaces:**

- Consumes: `Theme` and `\.theme` (Task 1), `GameState.tableOrder(viewer:)` (Task 2).
- Produces:
  - `func seatPoint(index: Int, count: Int, in size: CGSize) -> CGPoint`: index 0 is at the bottom center, and the others follow clockwise on screen (angle `π/2 + 2π·index/count`, y pointing down). The ellipse radii are 47 % of the width and 46 % of the height, measured from the center.
  - `struct OvalTable: View` with `let state: GameState`, `let viewer: PlayerID?` and a showdown hook that Task 5 fills in:
    `var seatState: (Seat) -> SeatMark = { _ in .normal }` and `var onTapSeat: ((PlayerID) -> Void)? = nil`.
  - `enum SeatMark { case normal, selectable, selected, dimmed }`

- [ ] **Step 1:** Write `seatPoint` and `OvalTable` in `OvalTable.swift`:
  - A `GeometryReader` with an ellipse filled with `theme.surface` and stroked with `theme.rim` (7 pt).
  - A seat label for each seat in `state.tableOrder(viewer:)` at `seatPoint`. The label shows the name (`lineLimit(1)`, `minimumScaleFactor(0.7)`, max width 70 pt) and the stack, plus the marks from the spec:
    - the acting seat: an accent ring (static here, Task 6 adds the pulse)
    - folded: opacity 0.4
    - all-in: an "All-in" tag
    - in `.handComplete`: a `+n` or `−n` delta, green or red
  - The D disk at the point 0.75 of the way from the center to the dealer's seat.
  - The bet (`roundBet > 0`) at 0.57 of the way from the center: chip icon plus amount.
  - The pot in the center: chip icons plus "Pot n". With `state.pots.count > 1`, add a line underneath, e.g. "Main 1,020 · Side 260", with "Side 1", "Side 2", … when there are several side pots.
  - The chip icon is a small circle in `theme.chips[i]` with a dashed white border. Add the `ponytail:` comment for decorative chips here.
- [ ] **Step 2:** In `TableView`:
  - Replace the `List` with `OvalTable(state: state, viewer: session.me)`.
  - Keep the header, the dealer hint, "Your stack", "To call" and `bottom`, but drop the old `Pot` text.
  - Set `theme.background` as the screen background (ignoring the safe area) and `theme.text` as the foreground.
- [ ] **Step 3:** Run the app build. Expected: success.
- [ ] **Step 4: Manual check** in the simulator, iPhone SE (3rd generation) and iPhone 17 Pro Max, in both themes:
  - 2 players: heads-up, Review Focus 5
  - 6 players
  - 10 players with one name of 20+ characters: Review Focus 1
  - one eliminated player: the seat disappears from the oval
  - the viewer busted: Review Focus 2
- [ ] **Step 5: Commit** `feat(app): oval table`

### Task 4: Themed action bar and next-hand bar

**Files:**

- Modify: `App/Sources/Theme.swift` (add the button style)
- Modify: `App/Sources/ActionBar.swift`
- Modify: `App/Sources/ShowdownView.swift` (`NextHandBar` only)

**Interfaces:**

- Produces: `struct ThemeButtonStyle: ButtonStyle` with `init(_ role: Role = .primary)`, where `enum Role { case primary, fold }`. Primary uses the accent fill with `theme.background` as the text color. Fold uses the `theme.fold` fill with `theme.text`. Full width, 10 pt corner radius, bold, opacity 0.4 when disabled (read `@Environment(\.isEnabled)` in a wrapper view).

- [ ] **Step 1:** Add `ThemeButtonStyle` to `Theme.swift`.
- [ ] **Step 2:** In `ActionBar`:
  - Fold uses `.fold`, Check/Call and Bet/Raise use `.primary`.
  - Keep the slider and the quick picks as their own row above the buttons.
  - The quick picks get a bordered capsule in `theme.muted`.
  - The logic (`request`, the all-in confirmation, `onChange(of: state.version)`) stays untouched.
- [ ] **Step 3:** `NextHandBar` uses `ThemeButtonStyle()`.
- [ ] **Step 4:** Run the app build. Expected: success.
- [ ] **Step 5: Manual check:** In both themes, play one hand with a bet, a raise through the slider, a quick pick and an all-in (the confirmation still appears). The disabled buttons are dimmed when it is not my turn.
- [ ] **Step 6: Commit** `feat(app): themed action bar`

### Task 5: Showdown on the oval

**Files:**

- Modify: `App/Sources/TableView.swift` (owns the selection)
- Modify: `App/Sources/ShowdownView.swift` (`ShowdownView` becomes the pot picker plus the "Pay out" bar)

**Interfaces:**

- Consumes: `OvalTable.seatState`, `OvalTable.onTapSeat` and `SeatMark` (Task 3), `ThemeButtonStyle` (Task 4).
- Produces: `ShowdownView(session:state:winners:pot:)` with `winners: Binding<[Set<PlayerID>]>` and `pot: Binding<Int>`. It shows the pot picker (only when `state.pots.count > 1`) and "Pay out". Non-runners see the existing waiting text.

- [ ] **Step 1:** In `TableView`, add `@State private var winners: [Set<PlayerID>] = []` and `@State private var pot = 0`. Reset both in `.onChange(of: state.pots, initial: true)`. This moves the existing reset out of `ShowdownView`.
- [ ] **Step 2:** In `.showdown` with `session.canRunHand`, pass `OvalTable` this mapping:
  - seats eligible for `state.pots[pot]`: `.selectable`
  - seats chosen for that pot: `.selected`
  - all other seats: `.dimmed`
  - `onTapSeat` toggles the seat in `winners[pot]`, but only for eligible seats.

  In every other phase, `seatState` stays at the default.
- [ ] **Step 3:** In `OvalTable`:
  - `.selected` shows the accent ring and a ✓ after the stack.
  - `.dimmed` uses opacity 0.3.
  - `.selectable` shows a thin `theme.muted` ring.
  - The tap gesture is active only when `onTapSeat != nil`.
- [ ] **Step 4:** Rewrite `ShowdownView`:
  - The pot picker is a segmented `Picker` with the labels "Main n" and "Side k n", bound to `pot`.
  - "Pay out" uses `ThemeButtonStyle()` and is disabled while `session.isSending || winners.contains { $0.isEmpty }`.
  - `payOut()` keeps its seat-order logic, reading from the binding.
- [ ] **Step 5:** Run the app build. Expected: success.
- [ ] **Step 6: Manual check:**
  - A showdown with a side pot, run by the host and run by a dealer who is not the host. "Pay out" stays disabled until both pots have a winner, and the payout matches the selection.
  - A pot the runner is not eligible for (Review Focus 3).
  - A non-runner sees the waiting text.
- [ ] **Step 7: Commit** `feat(app): pick showdown winners on the table`

### Task 6: Animations and haptics

**Files:**

- Modify: `App/Sources/OvalTable.swift`
- Modify: `App/Sources/TableView.swift`

- [ ] **Step 1: Pulse.** The acting seat's ring pulses with `phaseAnimator([false, true])`, between opacity 1 and 0.4, ease-in-out, about 0.8 s per phase.
- [ ] **Step 2: Numbers.** Seat stacks, bet amounts, the pot and "Your stack" get `.contentTransition(.numericText())`.
- [ ] **Step 3: Bets into the pot.** The bet views get `.transition(.asymmetric(insertion: .opacity, removal: .offset(toward center).combined(with: .opacity)))`, where the offset is the vector from the bet's point to the center. `OvalTable` gets `.animation(.easeInOut(duration: 0.4), value: state.version)`. Add the `ponytail:` comment for the missing pot-to-winner animation here.
- [ ] **Step 4: Win haptic.** In `TableView`, add a computed `iWon: Bool` (the phase is `.handComplete` and my seat's `stack > stackAtHandStart`) and `.sensoryFeedback(.success, trigger: iWon) { _, won in won }`. It fires once, when `iWon` turns true, and not again on later state changes in the same hand.
- [ ] **Step 5:** Run the app build. Expected: success.
- [ ] **Step 6: Manual check:**
  - Bets slide into the pot when the street changes.
  - Numbers roll when they change.
  - The ring pulses only at the acting seat.
  - The haptic fires on a real device when I win. The simulator has no haptics, so in the simulator just check that nothing breaks.
- [ ] **Step 7: Commit** `feat(app): table animations and win haptic`

### Task 7: Final checks and PR

- [ ] **Step 1:** Run `swift test` and the app build. Expected: both succeed.
- [ ] **Step 2: Manual check** of the full matrix from the spec's Testing section, plus Review Focus 4: switching the appearance while the leave confirmation is showing.
- [ ] **Step 3:** Amend the spec: under "Seats", add one line saying that the seat order comes from `GameState.tableOrder(viewer:)` in `PokerCore`. Commit this as `docs: note the core seat order helper in the redesign spec`.
- [ ] **Step 4:** Open the PR against `main`, linking the spec and the plan. It is a UI PR, so it waits for the user's review and gets no auto-merge.
