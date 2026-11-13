# AGENTS.md

iOS app that replaces the poker chip case for a home Texas Hold'em game, play money only. See [README.md](README.md) for the full description.

## Commands

Run both from the repo root before opening a PR; CI runs the same two.

- Package tests (macOS, no device needed): `swift test`
- App build:

  ```sh
  brew install xcodegen
  xcodegen generate --spec App/project.yml
  xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet
  ```

## Layout

- `Sources/PokerCore`: game rules, pots, commands, wire types. No dependencies.
- `Sources/PokerNet`: networking, depends on `PokerCore`.
- `Sources/PokerSession`: session state and save file, depends on `PokerCore` and `PokerNet`.
- `App/Sources`: SwiftUI app. It has no unit tests and is tested manually in simulators.
- `Tests/<Target>Tests`: Swift Testing, one test target per library.
- `docs/PROTOCOL.md`: the wire protocol. Update it in the same PR as any wire-format change.

## Rules

- Edit `App/project.yml` for project settings. `App/PokerChipCase.xcodeproj` and `App/Info.plist` are generated and gitignored.
- `App/Config/Local.xcconfig` holds per-developer signing settings and stays local.
- Swift 6 language mode with strict concurrency.
- Write code, comments, docs, and commits in English.
- Commits follow Conventional Commits with an optional scope, e.g. `fix(app): …`, `refactor: …`, `docs: …`.

## Planning workflow

- Design specs go in `docs/superpowers/specs/YYYY-MM-DD-<topic>.md`.
- Implementation plans go in `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` and are committed before implementation starts.
- `.superpowers/` holds local run state (ledgers, briefs) and stays local.
