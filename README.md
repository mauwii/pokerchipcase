# PokerChipCase

An iOS app that replaces the poker chip case at a Texas Hold'em night among friends – everything except the deck of cards. Players use real cards, every player uses the app on their own iPhone, and betting happens in the app. Play money only, no real money.

## Build

```sh
brew install xcodegen
xcodegen generate --spec App/project.yml
open App/PokerChipCase.xcodeproj
```

For a real device create `App/Config/Local.xcconfig` with `DEVELOPMENT_TEAM = <your team ID>` (and, if needed, your own `PRODUCT_BUNDLE_IDENTIFIER`). Edit `App/project.yml`, never the generated project or `Info.plist`.

## Test

`swift test` (macOS, no iPhone needed). The app itself is tested manually in several simulators.

## Protocol

See [docs/PROTOCOL.md](docs/PROTOCOL.md) for porting to other platforms.

## License

MIT
