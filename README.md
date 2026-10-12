# buenos-dias

mDNS / DNS-SD (Bonjour, zeroconf) for Roku SceneGraph channels, written in plain BrightScript.

- **`MdnsResponder`**: advertises a service on the LAN and answers PTR, SRV, TXT and A queries for it.
- **`MdnsBrowser`**: discovers instances of a service type and resolves their host, port, address and TXT records.

Both are `Task` nodes. No native code or extra Roku permissions are needed.

## Install

### With [ropm](https://github.com/rokucommunity/ropm) (recommended)

```sh
npx ropm install mdns@npm:buenos-dias
```

ropm copies the components into your channel and prefixes their names with the alias (`mdns` here). Create them as `mdns_MdnsResponder` and `mdns_MdnsBrowser`. The examples below use the unprefixed names.

### Manually

Copy `src/components/mdns/` into your channel's `components/` folder. The components keep their unprefixed names.

## Advertise a service

```xml
<MdnsResponder id="mdns" serviceType="_myapp._udp" port="16809" />
```

```brightscript
m.mdns = m.top.findNode("mdns")
m.mdns.txt = { version: "1", secure: true }
m.mdns.control = "RUN"

' later, to withdraw the service immediately (sends an RFC 6762 goodbye)
m.mdns.control = "STOP"
```

| Field | Type | Default | |
|---|---|---|---|
| `serviceType` | string | **required** | eg. `_myapp._udp` (`.local` optional) |
| `port` | integer | **required** | port your service listens on |
| `instanceName` | string | device friendly name | must not contain `.` |
| `hostName` | string | instance name with non-alphanumerics replaced by `-` | target of the SRV / A records |
| `ipAddress` | string | active interface | otherwise re-read on every announcement, so DHCP changes are picked up |
| `txt` | assocarray | `{}` | `true` values are written as bare keys |
| `ttl` | integer | `4500` | for PTR / TXT records; SRV / A records use `min(ttl, 120)` |
| `reannounceInterval` | integer | `1200` | seconds between unsolicited announcements, `0` to disable |
| `advertising` | boolean | output | `true` while running |
| `error` | string | output | set if the task could not start |

The task reads its config when it starts, so set the fields before `control = "RUN"`.

## Discover services

```brightscript
m.browser = CreateObject("roSGNode", "MdnsBrowser")
m.browser.serviceType = "_myapp._udp"
m.browser.timeout = 5 ' seconds, 0 = until control = "STOP"
m.browser.observeField("services", "onServices")
m.browser.control = "RUN"

sub onServices(event as object)
    for each service in event.getData()
        if service.resolved
            print service.name; " -> "; service.ipAddress; ":"; service.port
        end if
    end for
end sub
```

`services` is replaced every time the set changes. Each entry has:

`name`, `fullName`, `serviceType`, `hostName`, `port`, `ipAddress`, `ipv6Address`, `txt` (assocarray), and `resolved` (`true` once both `port` and `ipAddress` are known).

The browser re-queries at doubling intervals and sends follow-up queries for any missing SRV, TXT or A records. Instances are removed when they send a goodbye.

## Limitations

- IPv4 only for advertising. The browser reads AAAA records but the responder doesn't publish them.
- No name probing or conflict resolution (RFC 6762 §8.1–8.2). Give each device a unique `instanceName` / `hostName` if several run on the same LAN.
- Responses are always multicast. Unicast replies (the QU bit) and legacy unicast queries aren't supported.
- Instance names containing `.` aren't supported.

## Development

```
src/components/mdns/   the library (this is all that gets published)
demo/                  sample channel that advertises _adge._udp and runs a UDP command server
```

```sh
npm install
npm run lint     # BrighterScript validation of the library and the demo
```

To run the demo, open the repo in VS Code with the BrightScript extension, set your device's `host` / `password` in `.vscode/launch.json`, and launch. The demo pulls the library in from `src/` (see the `files` setting in `launch.json` and `demo/bsconfig.json`).

Publish with `npm publish`. The package contains `src/**` only.
