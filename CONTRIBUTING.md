# Contributing

Thanks for your interest in PokerChipCase. Bug reports, ideas and pull requests are all welcome.

## Before you start

- Look at issues labeled [`good first issue`](https://github.com/mauwii/pokerchipcase/labels/good%20first%20issue) for a small first step.
- For a bigger change (a new feature, a protocol change, a port to another platform) open an issue first, so we can agree on the approach before you put time in.
- Report security problems privately, see [SECURITY.md](SECURITY.md).

## Setup

You need a Mac with Xcode (Swift 6) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate --spec App/project.yml
open App/PokerChipCase.xcodeproj
```

To run on a real iPhone, create `App/Config/Local.xcconfig` with `DEVELOPMENT_TEAM = <your team ID>`. The file stays local.

Launch the app with the argument `-debugTable` to get a table full of bots on a single simulator.

## Checks

Run both from the repo root before you open a pull request. CI runs the same two.

```sh
swift test
xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet
```

The libraries in `Sources/` have unit tests in `Tests/`. Add or update tests for changes there. The SwiftUI app in `App/Sources` has no unit tests; describe what you checked by hand in the simulator.

## Rules

The full list is in [AGENTS.md](AGENTS.md). The ones that matter most:

- Swift 6 language mode with strict concurrency.
- Code, comments, docs and commits in English.
- Edit `App/project.yml`, never the generated `App/PokerChipCase.xcodeproj` or `App/Info.plist`.
- A change to the wire format updates [docs/PROTOCOL.md](docs/PROTOCOL.md) in the same pull request.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), e.g. `fix(app): …`, `feat(core): …`, `docs: …`.

## Pull requests

- Keep one topic per pull request. Small fixes are welcome.
- Fill in the [pull request template](.github/pull_request_template.md): what and why, and how you tested it.

## AI-assisted contributions

Contributions written with AI tools are fine, as long as you have read and understood every change and can answer questions about it. The repo ships optional Claude Code settings in `.claude/`; you don't need them to contribute.

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
