# PokerChipCase – Design

Date: 2026-11-11

## Goal

An iOS app that replaces the poker chip case at a Texas Hold'em night among friends – everything except the deck of cards. Players use real cards, every player uses the app on their own iPhone, and betting happens in the app. Play money only, no real money.

**Success means:** a complete tournament night without the case, and nobody has to do any math.

## Decisions

| Topic | Decision |
|---|---|
| Platform | iOS only (iOS 17+), Swift/SwiftUI |
| License | Open source, MIT (compatible with the App Store; GPL is not) |
| Android | Not by us. A documented protocol (`docs/PROTOCOL.md`) lets community ports play at the same table |
| Game | No-Limit Texas Hold'em, tournament. Cash game later |
| Communication | Local, no internet: newline-delimited JSON over TLS/TCP with `Network.framework`, Bonjour discovery, `includePeerToPeer = true` (works with a router **and** directly phone to phone via AWDL) |
| Encryption | TLS with a pre-shared key derived from a table code |
| Authority | The host is the single source of truth. Clients only send requests and display the state the host sends |
| Host | A player's phone (plays along). Separate table display (iPad) later |
| Cards/showdown | The app knows no cards. The dealer of the hand picks the winner(s) of each pot; the host can do it as a fallback |

## Out of scope (MVP)

- Cash game, rebuys, late join
- Separate table display (iPad) – prepared in the architecture, since it is just a client without a seat
- Pre-actions ("check/fold", "call any")
- Antes
- Accounts, cloud, statistics across nights
- Protection against deliberate cheating
- Android app

## Architecture

```text
pokerchipcase/
  Package.swift              Swift package with two targets
  Sources/PokerCore/         game logic + protocol types (no UI, no networking)
  Sources/PokerNet/          host/client over Network.framework
  Tests/PokerCoreTests/
  Tests/PokerNetTests/
  App/                       Xcode project, SwiftUI, depends on the package
  docs/PROTOCOL.md
  .github/workflows/ci.yml
```

Both package targets also run on macOS – logic and networking are testable without an iPhone.

### PokerCore

A pure function: `apply(state, command) -> Result<State, Rejection>`. `State` is a `Codable` value type. No clock and no randomness in the core: time and randomness (first button) come in as input, so tests are deterministic.

Contains:

- Tournament config: starting stack, blind structure (list of levels: SB, BB, duration), presets
- Seats in table order, button, small/big blind
- Phases: `lobby → preflop → flop → turn → river → showdown → handEnd → … → finished`
- Legal actions: fold, check, call, bet, raise, all-in
- No-limit rules: min raise = size of the last full raise; an incomplete all-in raise does not reopen the betting
- Heads-up: the button posts the small blind and acts first preflop
- Pots: main pot and side pots from the all-in players' bets
- Payout per pot to one or more winners; on a split an odd chip goes to the first eligible winner left of the button
- Elimination at stack 0, tournament ends when one player is left, ranking
- Button moves to the next active player (simplified rule, no dead-button logic)
- Blind levels: level end as a timestamp, or remaining time while paused; a new level applies from the next hand
- History: list of all previous states for undo

### Protocol

Details in `docs/PROTOCOL.md`. Every message is JSON with an envelope:

```json
{ "v": 1, "type": "command", "id": "uuid", "payload": { } }
```

Client → host:

- `hello` – protocol version, name, optional reconnect token
- `command` – every game command: actions (fold/check/call/bet/raise/all-in), showdown result, host commands (start, pause, resume, undo, fold/check for an absent player, remove player). `PokerCore` checks who may send which command.

Host → client:

- `welcome` – token and seat
- `ack` – for every `command`: `ok` or `rejected` with a reason
- `state` – the complete table state after every change
- `error` – a machine-readable code (for example `versionMismatch`)

The client never changes the state itself. After sending it shows "sending…" until the `ack` arrives. Everything it displays comes from the last `state`.

The state contains no secrets (all stacks are public), so every client gets the same snapshot.

### PokerNet

- **Host:** `NWListener` with TCP + TLS-PSK, one JSON message per line (WebSocket was dropped: its handshake needs URL endpoints, Bonjour/AWDL deliver service endpoints), advertises the Bonjour service `_pokerchipcase._tcp` with the table name.
- **Client:** `NWBrowser` lists nearby tables; connects with the same parameters.
- Both use `includePeerToPeer = true`.
- The host device connects to its own server as a regular client – a single code path.
- **Encryption:** the host generates a 4-digit table code. Key = HKDF-SHA256 (CryptoKit) over the code with the fixed salt `pokerchipcase-v1`. Cipher suite `TLS_PSK_WITH_AES_128_GCM_SHA256`, TLS 1.2 (as in Apple's peer-to-peer sample). A 4-digit code does not protect against targeted attacks – the goal is everyday confidentiality and that nobody joins the wrong table by accident.

### App (SwiftUI)

- **Start:** create table / join table (list from Bonjour, then enter the code), enter name
- **Lobby (host):** tournament settings with presets, show the table code, drag & drop players into seat order, button random or manual, start
- **Table view (everyone):** always visible – own stack large, pot, amount to call, all players with stack and bet of the round, active player highlighted, current blind level and remaining time. Action buttons (fold, check/call, bet/raise with slider and quick picks ½ pot / pot / all-in) only enabled on your turn, greyed out otherwise. All-in needs confirmation. Vibration when it is your turn
- **Dealer hints:** "You deal", "Deal the flop", "Deal the turn", "Deal the river"
- **Showdown (dealer of the hand):** pots listed, tap the winner(s) per pot (multiple = split)
- **Host menu:** pause/resume, undo, fold/check for an absent player, remove player
- **End:** ranking
- The display stays on during the game (`isIdleTimerDisabled`)
- The host saves the state including history as JSON in Application Support after every change; on launch it offers "Resume game"

## Error handling

| Case | Behavior |
|---|---|
| Client loses connection | Seat stays. The client finds the table via Bonjour and reconnects with its token. If it is their turn, the game waits; the host can fold/check for them manually. No automatic timeout |
| Host app crashes / is closed | Relaunch → "Resume game" from the saved file. Clients reconnect |
| Invalid action (double tap, wrong player, raise too small) | `ack rejected` with a reason; state unchanged |
| Protocol version mismatch | Join rejected with code `versionMismatch`; the app shows "Please update the app" |
| Wrong table code | TLS handshake fails → "Wrong code" |
| "Local network" permission denied | Explanation screen with a link to Settings |

## Tests

- **PokerCore (focus):** unit tests for side pots, min raise and incomplete all-ins, heads-up rule, odd chip on splits, elimination, tournament end, blind level changes, undo. Scenario tests that play complete hands as command sequences.
- **PokerNet:** integration tests on macOS – host plus several clients over `localhost`: join, wrong code, version mismatch, reconnect with token.
- **App:** manually in the simulator (several simulators at one table) and on real devices.
- **CI:** GitHub Actions on a macOS runner: `swift test` for the package, `xcodebuild build` for the app.

## Later

- Table display (iPad) as a client without a seat
- Cash game with rebuys and settlement
- Pre-actions
- Antes
- TestFlight / App Store
