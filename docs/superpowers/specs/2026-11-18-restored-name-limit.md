# Restored name limits

Issue: [#139](https://github.com/mauwii/pokerchipcase/issues/139).

## Problem

The name field limits edits to 32 characters, but an older stored preference is
shown before any edit happens. Older host saves can also contain an overlong
host name, including in their undo history.

## Behavior

- Apply the existing name-field limit when the start screen appears, as well as
  after edits. Preserve empty names and whole Unicode characters.
- Decode host snapshots with the host's name normalized by the existing
  `TableHost.seatName` policy, including its byte limit and empty-name fallback.
- Keep that display name consistent in undo history. Preserve player IDs,
  tokens, game versions, chips, cards, clocks, and history length.
- Preserve guest names and the existing save format. No wire-format change.

## Design

Keep the network name policy in PokerNet. Add a small PokerCore operation for
renaming one seat in the current state and existing undo states, without
recording a game action. HostSnapshot decoding uses that operation after
decoding the same four fields it already stores.

The start screen applies its current character-limit rule before reloading
saved tables. It does not adopt the network policy's fallback for an empty
input field.

## Verification

Use library tests for legacy snapshot decoding, Unicode, byte limits, and undo
preservation. Use XCUITest for initial name display and persistence after
relaunch. Run lint, package tests, DocC, the simulator app build, and the UI suite
required by AGENTS.md. Verify new regression cases fail before the fixes.
