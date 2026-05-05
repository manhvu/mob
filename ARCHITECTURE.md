# Dala — Architecture

## Deploy model

### Initial deploy (`mix dala.deploy --native`)

Requires USB. Does a full push:
- Compiles native code (APK for Android, iOS app bundle)
- Installs the app on the device via adb / xcrun
- Copies the compiled BEAMs to the device
- Starts the BEAM runtime

USB is only required for this step. Once the base app is installed and the
BEAM is running, all subsequent updates go through Erlang distribution.

### Subsequent deploys (`mix dala.deploy`)

No USB required (unless the device isn't already connected via dist). Does a
lightweight push:
- Compiles BEAMs
- Saves them to the dala_dev server
- dala_dev distributes the updated modules to connected devices via Erlang
  distribution (`:rpc.call` / `nl/1`)

If no device is connected via dist yet, fall back to USB push (same as
`--native` minus the native build step).

## Erlang distribution

Distribution is the backbone of the development loop. Once the base app is
installed, the BEAM node on the device connects to (or accepts a connection
from) the Mac's node and stays connected. All code updates, log streaming,
and remote inspection go through this channel.

Node naming convention:
- Android: `dala_demo_android@127.0.0.1` (USB tunnel via `adb forward`)
- iOS simulator: `dala_demo_ios@127.0.0.1` (simulator shares Mac network stack)
- iOS physical / Android wireless: device's LAN IP (future)

Cookie: `:dala_secret` (dev only, not for production use)

## Connection lifecycle

```
USB (once)
  └─ mix dala.deploy --native   → installs APK/IPA + BEAMs, starts BEAM
  └─ mix dala.connect           → sets up port forward, joins Erlang cluster

WiFi / dist (ongoing)
  └─ mix dala.deploy            → compile + push BEAMs via dist
  └─ mix dala.watch             → auto-push on file save via dist
  └─ dala_dev dashboard         → live logs, deploy buttons, device status
```

## dala_dev server role

The dala_dev server (`mix dala.server`) is the Mac-side hub:
- Discovers connected devices (adb + xcrun simctl)
- Streams logs from all connected devices
- Holds the latest compiled BEAMs and distributes them to devices via dist
- Provides a dashboard UI for deploy, log filtering, and device status

It is intentionally a dev-only tool — not shipped with the app, not running
on the device.
