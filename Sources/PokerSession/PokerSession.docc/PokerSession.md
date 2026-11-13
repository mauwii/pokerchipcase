# ``PokerSession``

Observable session state and the save file for the app.

## Overview

PokerSession ties the game and the network together for the UI: a ``TableSession`` wraps hosting or joining a table and publishes what the views display. It depends on PokerCore and PokerNet.

## Topics

### Session

- ``TableSession``
- ``ConnectionStatus``
- ``SessionProblem``

### Display helpers

- ``DealerHint``
- ``QuickPick``

### Persistence

- ``SaveFile``
- ``SeatTicket``
