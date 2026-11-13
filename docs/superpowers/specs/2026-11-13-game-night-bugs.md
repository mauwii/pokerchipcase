# Game-night bug round

Five deferred bugs that hurt a real game night, fixed in one PR before the visual redesign: #50, #41, #33, #34, #20.

## #50 Wrong code over Bonjour keeps the guest connecting

**Finding.** Probed on macOS with a `TableHost` and an `NWConnection` using `PSK.parameters` and a wrong code:

| Endpoint | Result |
|---|---|
| `127.0.0.1:<port>` | `waiting(-9820: bad MAC)` at once |
| `<LAN IP>:<port>` | `waiting(-9820: bad MAC)` at once |
| `.service(name:type:…)` (what guests use) | stays in `preparing` for 40+ s, no error |
| `.service`, correct code | `ready` in < 1 s |

Turning off peer-to-peer, forcing IPv4 or requiring Wi-Fi does not change the `.service` result. Network.framework keeps retrying a Bonjour service after a failed TLS handshake and never reports the error, so `MessageChannel.fail` is never called.

**Fix.**

1. `MessageChannel(to:code:)` with a `.service` endpoint first resolves it: a plain TCP connection to the service, and on `ready` its `currentPath.remoteEndpoint`. That connection is cancelled, and the TLS connection goes to the resolved address, where a failed handshake ends the connection. If the service is not advertised (host away), resolution stays in `preparing` until it comes back. This is the same behavior as today's reconnect.
2. Classification: an error before the TLS connection reached `.ready` is `ChannelError.handshakeFailed` ("Wrong code", final, no retry). The exceptions are errors that mean the host was not reachable: `.dns`, and POSIX `ECONNREFUSED`, `ETIMEDOUT`, `EHOSTUNREACH`, `EHOSTDOWN`, `ENETUNREACH`, `ENETDOWN`. Without these exceptions, every reconnect attempt to a stopped host would become "Wrong code". Errors after `.ready` and errors while resolving stay plain errors and are retried.

The host sees one extra TCP connection per connect attempt. It fails before TLS and is dropped.

#36 (a TLS error during host suspension counts as a wrong code) stays open. This change widens what counts as a handshake failure only for errors before `.ready` that are not "unreachable".

## #41 Save with a host token but no host seat

`TableSession.host` looks up the host seat inside the existing guard and throws `CocoaError(.fileReadCorruptFile)`. There is no force-unwrap.

## #33 Guests are not told when the host ends the table

New error code `tableClosed`, sent as a final `error` (connection closed). This reuses the existing envelope and the final-error path, so no new message type is needed. An older client treats the unknown code like a dropped connection, which is today's behavior.

- `TableHost.end()` sends `tableClosed` with `sendAndClose` on every open connection, then stops listening. `stop()` stays silent, because tests use it to simulate a host that vanished.
- `TableSession.leave()` calls `end()` on the host device.
- `TableClient` maps it to `ClientFailure.tableClosed`. The app shows "The host ended the table" in the existing failure alert. OK returns to the start screen, and the session deletes the guest's seat ticket as for any final failure.

## #34 Player removed mid-game stays connected

A mid-game `.removePlayer` keeps the seat (folded, stack 0, eliminated), so the "no seat → `removed`" rule does not catch it. After a successful `.removePlayer(player)`, the host also drops that player's token and sends `removed` to (and closes) that player's connections. Busted players keep their token and stay connected as spectators.

## #20 Swallowed errors

`TableSession.problem: SessionProblem?`: `.saveFailed`, `.deleteFailed`, `.sendFailed`, `.listenFailed`. Each case carries the error's `localizedDescription`. The app shows it in the banner like `rejection`, translated in `Messages.swift`.

| Source | Set | Cleared |
|---|---|---|
| host save in `onChange`, ticket save on `welcome` | `.saveFailed` | next successful save |
| thrown `client.send` | `.sendFailed` | next `send` |
| `ensureListening` in `appBecameActive` | `.listenFailed` | next successful `appBecameActive` |
| `SaveFile.delete()` in `leave()` and after a final failure | `.deleteFailed` | next successful `leave()` |

- `SaveFile.delete()` now throws, but a missing file is still no error.
- `leave()` returns `false` when deleting failed. `TableScreen` then stays open with the banner instead of returning to a start screen that would offer the stale save, and "Leave"/"End table" tries again. The failure alert is not shown again while the problem is `.deleteFailed`.
- `StartView`'s "Discard" buttons show an alert when deleting fails.
- The rollback in a failed `host()` start keeps `try?`: it already throws the start error.
