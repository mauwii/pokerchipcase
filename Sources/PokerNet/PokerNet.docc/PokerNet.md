# ``PokerNet``

Bonjour discovery and the TLS-PSK transport between the table host and its players.

## Overview

PokerNet lets one device host a table and others join it over the local network. The host runs a ``TableHost``, players find it with a ``TableBrowser`` and connect with a ``TableClient``. It depends on PokerCore for the message types.

## Topics

### Wire protocol

- <doc:Protocol>

### Hosting

- ``TableHost``
- ``HostSnapshot``
- ``TableCode``

### Joining

- ``TableBrowser``
- ``DiscoveredTable``
- ``BrowserStatus``
- ``TableClient``
- ``ClientEvent``
- ``ClientFailure``
- ``ClientError``
