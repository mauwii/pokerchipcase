# Table redesign

Replace the plain list on the table screen with an oval poker table, and add a per-device appearance setting with two themes. The change is app-only apart from one read-only helper in `PokerCore`; `PokerNet`, `PokerSession` and the wire protocol stay as they are.

## Context

Every player uses their own iPhone. A shared center display may come later and is out of scope. Mockups from the brainstorm are in `.superpowers/brainstorm/` (local, not committed): `visual-style.html` (theme directions), `layout.html` (oval vs. list) and `layout-v2.html` (oval table with 10 seats in four states).

## Scope

In scope: the table screen (`TableView`, `ActionBar`, `ShowdownView`, `NextHandBar`), the theme, and the appearance setting.

Out of scope, for a later spec: a redesign of the start, lobby and ranking screens beyond the theme tint, custom blind structures and starting stacks, and a pot-to-winner animation.

## Appearance setting and themes

- `@AppStorage("appearance")` stores `felt`, `dark` or `system`. The default is `system`. The setting is per device and never synced.
- The app root applies `.preferredColorScheme`: `.light` for `felt`, `.dark` for `dark`, and `nil` for `system`.
- The theme follows the color scheme: `.dark` gives the dark theme, and everything else gives felt. System sheets, alerts and forms therefore match the theme without extra work.
- New file `App/Sources/Theme.swift`:
  - `struct Theme` with the look tokens: table surface, rim, accent, seat background, primary and muted text, the fold button color and three chip colors
  - two static themes, `.felt` and `.dark`
  - an environment entry (`@Entry var theme`), set at the app root from `colorScheme`
- `.felt`: green felt surface with a wood rim, gold accent, dark brown background. `.dark`: near-black background, dark gray surface, one mint accent.
- Start, lobby and ranking stay forms. They only get `.tint(theme.accent)`.

## Settings screen

- New `SettingsView`: a segmented picker labeled "Felt / Dark / System" that is bound to `appearance`.
- It opens as a sheet from a gear button in the `StartView` toolbar.

## Oval table

The table fills the space between the header and the bottom area. The seat layout math is a pure function in its own file, so it can be tested later.

- **Seats:** all players not yet eliminated, evenly spaced on an ellipse in seat order. The view is rotated so that my seat is at the bottom. If I am eliminated or a spectator, the first remaining seat goes to the bottom. Eliminated players do not appear on the table. The order comes from `GameState.tableOrder(viewer:)` in `PokerCore`, which has tests; the app only places the seats on the ellipse.
- **A seat** shows the name and the stack. The name is truncated, and the text shrinks through `minimumScaleFactor` when space is tight. Extra marks:
  - the player to act: an accent ring that pulses gently
  - folded: dimmed
  - all-in: a small "All-in" tag
  - at hand end: the stack change as a green `+n` or a red `−n`
- **Dealer:** a small round "D" disk next to the dealer's seat, toward the center.
- **Bets:** about 60 % of the way from a seat to the center, shown as a chip icon with the amount.
- **Pot:** in the center, a chip stack icon with "Pot n". With side pots, one small line underneath, e.g. "Main 1,020 · Side 260".
- **Chips are decoration only:** one to three chip icons in the theme's chip colors, with no breakdown into chip values. `ponytail:` value-accurate chip stacks only if someone asks for them.
- **Header:** level, blinds, clock and the next level, as today. The dealer hint stays a banner that only the dealer sees.
- **Below the table:** my stack in large type, then "To call n", then the bottom area for the current phase.
- **Ten seats on the smallest iPhone** (375 pt wide) leave about 95 pt per seat around the ellipse, which is enough for a name and a stack.

## Action bar

The logic in `ActionBar.swift` stays the same: slider, quick picks and the all-in confirmation. Only the look changes:

- A `ThemeButtonStyle` gives the buttons their look. Fold uses the theme's fold color, and Check/Call and Bet/Raise use the accent.
- The slider and the quick picks sit in their own row above the buttons.

## Showdown

For the player who runs the hand (`session.canRunHand`):

- Winners are picked on the oval, by tapping seats. This replaces the toggle list.
- With more than one pot, a segmented picker above the table selects the pot, e.g. "Main 1,020 · Side 260". The selection is kept per pot.
- Only seats eligible for the selected pot can be tapped. The other seats are dimmed. A chosen seat gets an accent ring and a check mark.
- "Pay out" sits where the action bar usually is. It stays disabled until every pot has at least one winner.
- The existing reset of the selection when `state.pots` changes stays.

For everyone else: "Waiting for X to pick the winners", as today. The selection stays on the device of the player running the hand, so the protocol does not change.

"Next hand" (`NextHandBar`) uses the same button style.

## Animations and haptics

- The ring at the player to act pulses.
- Stacks, bets and the pot use `.contentTransition(.numericText())`.
- When a betting round ends, the bets move into the pot: a removal transition that moves each bet from its seat toward the center and fades it out.
- If I win chips in a hand, `.sensoryFeedback(.success)` fires.
- `ponytail:` no pot-to-winner animation yet. Add it once the rest feels right.

## Testing

The app has no unit tests. The table is checked by hand in the simulator:

- 2, 6 and 10 players
- iPhone SE (3rd generation) and iPhone 17 Pro Max
- both themes, and switching the setting while a table is open
- a showdown with a side pot
- a long player name
- a player who is eliminated or a spectator

`swift test` and the app build from AGENTS.md must still pass.
