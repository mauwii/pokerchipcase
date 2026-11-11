# PokerChipCase-Protokoll (Version 1)

Dieses Dokument beschreibt alles, was ein kompatibler Client (z. B. eine Android-App) braucht, um an einem PokerChipCase-Tisch mitzuspielen. Maßgeblich sind die Typen in `Sources/PokerCore/` und die Golden-Tests in `Tests/PokerCoreTests/WireTests.swift`.

## Transport

| | |
|---|---|
| Discovery | Bonjour/mDNS, Diensttyp `_pokerchipcase._tcp`, Instanzname = Tischname |
| Verbindung | WebSocket (Textframes mit UTF-8-JSON) über TLS über TCP |
| TLS | TLS 1.2, Pre-Shared-Key, Cipher Suite `TLS_PSK_WITH_AES_128_GCM_SHA256` |
| PSK | HKDF-SHA256 über den 4-stelligen Tisch-Code (UTF-8), Salt `pokerchipcase-v1` (UTF-8), 32 Byte Ausgabe |
| Peer-to-Peer | Auf iOS zusätzlich über AWDL (`includePeerToPeer`); andere Plattformen nutzen das gemeinsame WLAN |

Ein falscher Tisch-Code lässt den TLS-Handshake scheitern.

## Umschlag

Jede Nachricht in beide Richtungen:

```json
{"id":"<UUID>","payload":<Nutzlast>,"type":"<Typ>","v":1}
```

- `v` – Protokollversion. Weicht sie ab, wird die Nachricht abgelehnt.
- `id` – vom Absender erzeugte UUID (Großbuchstaben, mit Bindestrichen).
- `type` – bestimmt die Form von `payload`.
- Datumswerte sind Millisekunden seit 1970-01-01 UTC als Zahl.
- Dauern (`duration`, `pausedRemaining`) sind Sekunden als Zahl.

### Kodierung von Aufzählungen mit Werten

`Command`, `Action` und `AckResult` werden als Objekt mit genau einem Schlüssel kodiert – dem Fallnamen. Sein Wert ist ein Objekt mit den benannten Feldern, bei Fällen ohne Werte `{}`:

```json
{"act":{"action":{"raiseTo":{"amount":60}},"player":"B"}}
{"fold":{}}
```

Aufzählungen ohne Werte (`Phase`, `Street`, `Rejection`) sind einfache Strings.

## Client → Host

### `hello` – Beitritt oder Reconnect

```json
{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Anna","protocolVersion":1},"type":"hello","v":1}
```

`payload.token` (optional) ist das Token aus einem früheren `welcome`; damit übernimmt der Client nach einem Verbindungsabbruch seinen Sitz wieder.

### `command` – jeder Spielbefehl

```json
{"id":"00000000-0000-0000-0000-000000000001","payload":{"act":{"action":{"raiseTo":{"amount":60}},"player":"B"}},"type":"command","v":1}
```

| Befehl | Felder | Wer darf |
|---|---|---|
| `join` | `player`, `name` | nur der Host (erzeugt der Host selbst nach `hello`) |
| `removePlayer` | `player` | Host, nicht für sich selbst |
| `arrangeSeats` | `order` (alle Spieler-IDs) | Host, nur in der Lobby |
| `startTournament` | `button` | Host, mindestens 2 Spieler |
| `act` | `player`, `action` | der Spieler selbst, wenn er dran ist; der Host zusätzlich `fold`/`check` für andere |
| `resolveShowdown` | `winners` (pro Pot eine Liste von Spieler-IDs) | Dealer der Hand |
| `startNextHand` | – | Dealer der Hand oder Host |
| `pauseClock`, `resumeClock` | – | Host |
| `undo` | – | Host |

Aktionen (`action`): `fold`, `check`, `call`, `raiseTo` mit `amount` (Gesamteinsatz in dieser Setzrunde; Bet, wenn noch niemand gesetzt hat), `allIn`.

## Host → Client

### `welcome` – Antwort auf `hello`

```json
{"id":"…","payload":{"player":"B","token":"…"},"type":"welcome","v":1}
```

Das Token geheim halten und für Reconnects aufbewahren.

### `ack` – Antwort auf jede Client-Nachricht

```json
{"id":"00000000-0000-0000-0000-000000000001","payload":{"id":"00000000-0000-0000-0000-000000000001","result":{"rejected":{"reason":"notYourTurn"}}},"type":"ack","v":1}
```

`payload.id` ist die `id` der beantworteten Nachricht. `result` ist `{"ok":{}}` oder `{"rejected":{"reason":"<Rejection>"}}`.

Gründe: `notHost`, `notDealer`, `notYourTurn`, `invalidPhase`, `illegalAction`, `invalidAmount`, `unknownPlayer`, `duplicatePlayer`, `tableFull`, `tooFewPlayers`, `invalidShowdown`, `nothingToUndo`.

### `state` – kompletter Tischzustand

Wird nach jeder Änderung an alle Clients gesendet. Die wichtigsten Felder von `payload`:

| Feld | Bedeutung |
|---|---|
| `phase` | `lobby`, `betting`, `showdown`, `handComplete`, `finished` |
| `street` | `preflop`, `flop`, `turn`, `river` – zuletzt erreichte Straße |
| `seats[]` | in Tischreihenfolge: `id`, `name`, `stack`, `roundBet`, `handBet`, `folded`, `allIn`, `acted`, `mayRaise`, `stackAtHandStart`, `eliminatedRank` (fehlt, solange im Spiel) |
| `buttonIndex` | Index des Dealers in `seats` |
| `toActIndex` | Index des Spielers am Zug (fehlt, wenn niemand dran ist) |
| `currentBet`, `lastRaiseSize` | höchster Einsatz der Runde; Mindest-Raise = `currentBet + lastRaiseSize` |
| `pots[]` | nur im Showdown: `amount`, `eligible` (Spieler-IDs) |
| `clock` | `levelIndex`, `levelEndsAt` (Datum) oder `pausedRemaining` (Sekunden) |
| `config` | `startingStack`, `levels[]` mit `smallBlind`, `bigBlind`, `duration` |
| `hostID`, `handNumber` | |

Clients zeigen nur an, was im letzten `state` steht, und ändern ihn nie selbst.

### `error`

```json
{"id":"…","payload":"Bitte App aktualisieren","type":"error","v":1}
```

Für Fehler außerhalb eines Befehls, z. B. abgelehnter Beitritt wegen Versionskonflikt. Der Host schließt danach die Verbindung.

## Ablauf

```
Client                          Host
  | -- TLS-PSK-Handshake ------> |
  | -- hello ------------------> |
  | <------------------ welcome  |
  | <-------------------- state  |
  | -- command ----------------> |
  | <---------------------- ack  |
  | <-------------------- state  |   (an alle)
```

## Versionen

Ändert sich das Format inkompatibel, steigt `v`. Ein Host lehnt `hello` mit anderer `protocolVersion` mit einem `error` ab.
