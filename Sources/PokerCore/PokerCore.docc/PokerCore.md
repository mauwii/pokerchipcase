# ``PokerCore``

Game rules, pots, commands and wire types for a Texas Hold'em tournament.

## Overview

PokerCore holds the pure game logic: a ``Game`` applies ``Command`` values to a ``GameState`` and either succeeds or fails with a ``Rejection``. It also defines the messages that travel between host and clients. It depends on Foundation only.

## Topics

### Game state

- ``Game``
- ``GameState``
- ``Seat``
- ``Pot``
- ``Phase``
- ``Street``
- ``BlindClock``
- ``LegalActions``

### Configuration

- ``TournamentConfig``
- ``BlindLevel``
- ``Chips``
- ``PlayerID``

### Commands

- ``Command``
- ``Action``
- ``Rejection``

### Wire types

- ``Wire``
- ``ClientMessage``
- ``ServerMessage``
- ``Hello``
- ``Welcome``
- ``CommandRequest``
- ``Ack``
- ``AckResult``
- ``WireError``
- ``WireErrorCode``
