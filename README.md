# buenos-dias — zero-config Roku companion protocol

A Roku channel that advertises itself on the LAN via mDNS/Bonjour and accepts
commands (remote input, deep links, dynamic content) from a companion client
on the same network — no pairing code, no IP entry. The mDNS responder and
the discovery client both speak the multicast DNS wire format from scratch,
since BrightScript has no native Bonjour/mDNS API to call into.

## Why this exists

Roku's own External Control Protocol (ECP) covers basic remote/launch
commands, but nothing for app-defined companion commands or content
injection, and clients still have to find the device's IP through Roku's own
SSDP discovery flow. This project builds a self-contained alternative: the
channel announces itself on the LAN the same way a Chromecast or AirPlay
device does (mDNS/DNS-SD), and anything speaking the UDP command protocol
below can control it the moment it's found.

## Architecture

- [`source/components/networkBroadcastTask.brs`](source/components/networkBroadcastTask.brs) —
  runs on the Roku. Joins `224.0.0.251:5353` and answers mDNS PTR/SRV/A/TXT/NSEC
  queries for `_adge._udp.local` with a hand-built DNS response — BrightScript
  has no binary/Bonjour helpers, so the wire format is constructed and parsed
  byte-by-byte here. It also starts the command server below.
- [`source/components/udpServer.brs`](source/components/udpServer.brs) — a UDP
  command server on port `16809` that accepts `action:value` commands
  (`remote`, `deeplink`, `adContent`, `serviceAuth`, `content`) and republishes
  them as SceneGraph fields the rest of the channel observes
  (see [`videoscreen.brs`](source/components/videoscreen.brs)).
- [`client/discover.js`](client/discover.js) — the companion side. A small Node
  client that sends a multicast DNS query, decodes the response, and can
  immediately fire a command back at the discovered device — standing in for
  a real mobile companion app.

## Demo

```
cd client
npm install
node discover.js                                             # just discover devices on the LAN
node discover.js --remote select                              # discover, then send a "remote" command
node discover.js --deeplink "https://example.com/video.m3u8"   # discover, then push a deep link
```

Run this from a machine on the same LAN/subnet as a Roku with this channel
side-loaded and running (the `videoscreen` scene needs to be active, since
that's what starts `NetworkBroadcastTask`). Expect output like:

```
Searching for "_adge._udp.local" on the LAN (3000ms)...
Found: Living Room Roku._adge._udp.local  ip=192.168.1.42  port=16809  target=gdevice.local
Sending "deeplink:https://example.com/video.m3u8" to 192.168.1.42:16809...
Sent.
```

## Known issues / what production would need

- **Security** — the UDP control channel is effectively unauthenticated, and
  [`server.config.brs`](source/components/server.config.brs) ships static,
  plaintext tokens in source. Needs real per-device pairing (first-use code,
  rotating/derived tokens) before this handles anything sensitive — anyone on
  the same LAN can currently push commands to the device.
- **Multi-device collisions** — the SRV target (`gdevice.local`) is a fixed
  literal rather than derived per device, so two Rokus running this channel
  on the same LAN would advertise the same target name.
- **Not fully RFC 6762-compliant** — no response jitter before answering and
  no name probing/tie-breaking on startup. The responder now re-announces
  every 20 minutes (well under the 4500s/75 min record TTL) so peer caches
  stay warm even if nothing re-queries it, but there's still no goodbye
  (TTL 0) packet sent on shutdown, so a stopped instance lingers in caches
  until its TTL naturally expires.
- **No graceful shutdown** — the responder's receive loop has no signal to
  unwind and send a goodbye packet when the task is stopped or the channel
  exits; it just gets torn down.
- **Fragile parsing, now contained** — `ReadName` still doesn't follow DNS
  name-compression pointers in the general case (only the additional-records
  path does), which matters because the multicast group carries every
  device's mDNS traffic (Chromecasts, printers, HomeKit, etc.), not just this
  channel's own. A malformed packet is now caught per-message so it can't
  kill the whole responder, but the parser itself is still worth hardening.
- **No automated tests** around the binary DNS record encode/decode
  functions, which is exactly the kind of code most prone to silent
  off-by-one bugs.

## Repo layout

- `source/` — the Roku channel (BrightScript/SceneGraph)
- `client/` — the Node.js discovery + companion-command demo client
