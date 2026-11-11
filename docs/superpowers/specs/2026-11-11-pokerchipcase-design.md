# PokerChipCase – Design

Stand: 2026-11-11

## Ziel

Eine iOS-App, die beim Texas-Hold'em-Abend unter Freunden den Pokerkoffer ersetzt – alles außer dem Kartenspiel. Gespielt wird mit echten Karten, jeder Spieler nutzt die App auf seinem eigenen iPhone, gesetzt wird in der App. Es geht nur um Spielgeld, kein echtes Geld.

**Erfolg heißt:** Ein kompletter Turnierabend ohne Koffer, ohne dass jemand rechnen muss.

## Entscheidungen

| Thema | Entscheidung |
|---|---|
| Plattform | Nur iOS (ab iOS 17), Swift/SwiftUI |
| Lizenz | Open Source, MIT (verträgt sich mit App Store; GPL nicht) |
| Android | Nicht von uns. Dokumentiertes Protokoll (`docs/PROTOCOL.md`) ermöglicht Community-Portierungen, die am selben Tisch mitspielen können |
| Spielvariante | No-Limit Texas Hold'em, Turnier. Cash Game später |
| Kommunikation | Lokal, ohne Internet: WebSocket über `Network.framework`, Bonjour-Discovery, `includePeerToPeer = true` (funktioniert mit Router **und** direkt Handy-zu-Handy per AWDL) |
| Verschlüsselung | TLS mit Pre-Shared-Key, abgeleitet aus einem Tisch-Code |
| Autorität | Der Host ist die einzige Wahrheit. Clients senden nur Wünsche und zeigen den vom Host gesendeten Zustand an |
| Host | Ein Spieler-Handy (spielt mit). Separate Tisch-Anzeige (iPad) später |
| Karten/Showdown | App kennt keine Karten. Der Dealer der Hand wählt pro Pot den/die Gewinner |

## Nicht im Umfang (MVP)

- Cash Game, Rebuys, Late Join
- Separate Tisch-Anzeige (iPad) – architektonisch vorbereitet, da nur ein Client ohne Sitzplatz
- Vorab-Aktionen ("Check/Fold", "Call any")
- Antes
- Accounts, Cloud, Statistiken über mehrere Abende
- Schutz gegen absichtliches Schummeln
- Android-App

## Architektur

```
pokerchipcase/
  Package.swift              Swift Package mit zwei Targets
  Sources/PokerCore/         Spiellogik + Protokoll-Typen (kein UI, kein Netzwerk)
  Sources/PokerNet/          Host/Client über Network.framework
  Tests/PokerCoreTests/
  Tests/PokerNetTests/
  App/                       Xcode-Projekt, SwiftUI, hängt vom Package ab
  docs/PROTOCOL.md
  .github/workflows/ci.yml
```

Beide Package-Targets laufen auch auf macOS – Logik und Netzwerk sind damit ohne iPhone testbar.

### PokerCore

Reine Funktion: `apply(state, command) -> Result<State, Rejection>`. `State` ist ein `Codable`-Werttyp. Keine Uhr, kein Zufall im Kern: Zeit und Zufall (erster Button) kommen als Eingabe herein, damit Tests deterministisch sind.

Enthält:
- Turnier-Konfiguration: Startstack, Blind-Struktur (Liste von Levels: SB, BB, Dauer), Vorlagen
- Sitzplätze in Tischreihenfolge, Button, Small/Big Blind
- Phasen: `lobby → preflop → flop → turn → river → showdown → handEnd → … → finished`
- Erlaubte Aktionen: Fold, Check, Call, Bet, Raise, All-in
- No-Limit-Regeln: Min-Raise = Größe der letzten vollen Erhöhung; ein unvollständiges All-in-Raise öffnet die Setzrunde nicht erneut
- Heads-up: Button setzt Small Blind und handelt preflop zuerst
- Pots: Hauptpot und Side-Pots aus den Einsätzen der All-in-Spieler
- Auszahlung pro Pot an einen oder mehrere Gewinner; bei Split geht ein Restchip an den ersten berechtigten Gewinner links vom Button
- Ausscheiden bei Stack 0, Turnierende wenn ein Spieler übrig ist, Rangliste
- Button wandert zum nächsten noch aktiven Spieler (vereinfachte Regel, keine Dead-Button-Logik)
- Blind-Level: Level-Ende als Zeitstempel bzw. Restzeit bei Pause; neues Level gilt ab der nächsten Hand
- Historie: Liste aller bisherigen Zustände für "Rückgängig"

### Protokoll

Details in `docs/PROTOCOL.md`. Jede Nachricht ist JSON mit Umschlag:

```json
{ "v": 1, "type": "action", "id": "uuid", "payload": { } }
```

Client → Host:
- `hello` – Protokollversion, Name, optional Reconnect-Token
- `command` – jeder Spielbefehl: Aktionen (Fold/Check/Call/Bet/Raise/All-in), Showdown-Ergebnis, Host-Befehle (starten, pausieren, fortsetzen, rückgängig, für abwesenden Spieler folden/checken, Spieler entfernen). Wer welchen Befehl senden darf, prüft `PokerCore`.

Host → Client:
- `welcome` – Token und Sitzplatz
- `ack` – zu jeder Client-Nachricht: `ok` oder `rejected` mit Grund
- `state` – nach jeder Änderung der komplette Tischzustand

Der Client ändert nie selbst den Zustand. Nach dem Senden zeigt er "wird gesendet…", bis `ack` kommt. Alles, was er anzeigt, stammt aus dem letzten `state`.

Der Zustand enthält keine Geheimnisse (alle Stacks sind öffentlich), daher bekommt jeder Client denselben Snapshot.

### PokerNet

- **Host:** `NWListener` mit TCP + TLS-PSK + WebSocket, veröffentlicht Bonjour-Dienst `_pokerchipcase._tcp` mit Tischnamen.
- **Client:** `NWBrowser` listet Tische in der Nähe; Verbindung mit denselben Parametern.
- Beide mit `includePeerToPeer = true`.
- Das Host-Gerät verbindet sich intern als normaler Client mit seinem eigenen Server – ein einziger Code-Pfad.
- **Verschlüsselung:** Der Host erzeugt einen 4-stelligen Tisch-Code. Schlüssel = HKDF-SHA256 (CryptoKit) über den Code mit festem Salt `pokerchipcase-v1`. Cipher Suite `TLS_PSK_WITH_AES_128_GCM_SHA256`, TLS 1.2 (wie Apples Peer-to-Peer-Beispiel). Ein 4-stelliger Code ist kein Schutz gegen gezielte Angriffe – Zweck sind vertrauliche Übertragung im Alltag und dass niemand versehentlich am falschen Tisch landet.

### App (SwiftUI)

- **Start:** Tisch erstellen / Tisch beitreten (Liste aus Bonjour, dann Code eingeben), Name eingeben
- **Lobby (Host):** Turnier-Einstellungen mit Vorlagen, Tisch-Code anzeigen, Spieler per Drag & Drop in Sitzreihenfolge bringen, Button zufällig oder manuell, Start
- **Tisch-Ansicht (alle):** immer sichtbar – eigener Stack groß, Pot, zu callender Betrag, alle Spieler mit Stack und Einsatz der Runde, aktiver Spieler hervorgehoben, aktuelles Blind-Level und Restzeit. Aktions-Buttons (Fold, Check/Call, Bet/Raise mit Slider und Schnellwahl ½ Pot / Pot / All-in) nur aktiv, wenn man dran ist, sonst ausgegraut. All-in mit Bestätigung. Vibration, wenn man dran ist
- **Dealer-Hinweise:** "Du dealst", "Flop aufdecken", "Turn aufdecken", "River aufdecken"
- **Showdown (Dealer der Hand):** Pots aufgelistet, pro Pot Gewinner antippen (Mehrfachauswahl = Split)
- **Host-Menü:** Pause/Fortsetzen, Rückgängig, für abwesenden Spieler folden/checken, Spieler entfernen
- **Ende:** Rangliste
- Display bleibt während des Spiels an (`isIdleTimerDisabled`)
- Host speichert den Zustand inkl. Historie nach jeder Änderung als JSON in Application Support; beim Start wird "Spiel fortsetzen" angeboten

## Fehlerbehandlung

| Fall | Verhalten |
|---|---|
| Client verliert Verbindung | Platz bleibt. Client sucht den Tisch per Bonjour und verbindet sich mit Token neu. Ist er dran, wartet das Spiel; Host kann manuell für ihn folden/checken. Kein automatischer Timeout |
| Host-App stürzt ab / wird beendet | Neustart → "Spiel fortsetzen" aus gespeicherter Datei. Clients verbinden sich neu |
| Ungültige Aktion (Doppeltipp, falscher Spieler, zu kleiner Raise) | `ack rejected` mit Grund; Zustand unverändert |
| Protokollversion passt nicht | Beitritt abgelehnt: "Bitte App aktualisieren" |
| Falscher Tisch-Code | TLS-Handshake scheitert → "Code falsch" |
| Berechtigung "Lokales Netzwerk" verweigert | Erklärbildschirm mit Link zu den Einstellungen |

## Tests

- **PokerCore (Schwerpunkt):** Unit-Tests für Side-Pots, Min-Raise und unvollständige All-ins, Heads-up-Regel, Restchip bei Split, Ausscheiden, Turnierende, Blind-Level-Wechsel, Rückgängig. Szenario-Tests, die komplette Hände als Befehlsfolge durchspielen.
- **PokerNet:** Integrationstest auf macOS – Host plus mehrere Clients über `localhost`: Beitritt, falscher Code, Versionskonflikt, Reconnect mit Token.
- **App:** Manuell im Simulator (mehrere Simulatoren an einem Tisch) und auf echten Geräten.
- **CI:** GitHub Actions auf macOS-Runner: `swift test` für das Package, `xcodebuild build` für die App.

## Später

- Tisch-Anzeige (iPad) als Client ohne Sitzplatz
- Cash Game mit Rebuys und Abrechnung
- Vorab-Aktionen
- Antes
- TestFlight / App Store
