# Getting Started

Mob runs on iOS and Android. Pick your target — you don't need both.

→ [iOS only](#ios-only)
→ [Android only](#android-only)
→ [Both platforms](#both-platforms)

---

## iOS only

### What you need

- macOS
- Xcode 15 or later (`xcode-select --install` for command-line tools)
- Elixir 1.18 or later with Hex: `mix local.hex`
- `mob_new` installed: `mix archive.install hex mob_new`

That's enough to run on the **iOS Simulator**. For a **physical iPhone**, you also need:

- An Apple ID — free at https://appleid.apple.com
- Xcode signed in with that Apple ID: open Xcode → Settings → Accounts → [+]
- (For App Store distribution only) Apple Developer Program — $99/year.
  Free accounts can deploy to your own devices; profiles expire every 7 days.

### Create a project

```bash
mix mob.new my_app
cd my_app
mix mob.install
```

`mix mob.install` downloads the pre-built OTP runtime for iOS and writes your `mob.exs`.

### Verify your environment

```bash
mix mob.doctor
```

Fix any failures before continuing. See [Troubleshooting](troubleshooting.md) if needed.

### Run on the iOS Simulator

Boot a simulator from Xcode → Open Simulator, or:

```bash
xcrun simctl boot "iPhone 16 Pro"
open -a Simulator
```

Then deploy:

```bash
mix mob.deploy --native --ios
```

This builds the `.app` bundle, installs it in the simulator, and pushes your BEAM files.
Subsequent deploys without `--native` are faster — they push only changed `.beam` files:

```bash
mix mob.deploy --ios
```

### Run on a physical iPhone

There are three one-time steps before your first deploy. Do them in order.

#### Step 1 — Trust the Mac

Connect your iPhone to your Mac with a USB cable. The phone will show:

> **"Trust This Computer?"**

Tap **Trust**, then enter your passcode. If this dialog doesn't appear, unplug and
replug the cable, or try a different port.

#### Step 2 — Enable Developer Mode on the iPhone

This is required on iOS 16 and later. You only do it once per phone.

On the iPhone: **Settings → Privacy & Security → Developer Mode → turn ON**

The phone will warn you and ask to restart. Tap **Restart**. After it reboots, a
dialog appears asking to confirm — tap **Enable** and enter your passcode.

> If you don't see Developer Mode in Settings, make sure the phone is connected to
> the Mac and Xcode is open. Xcode needs to recognise the device at least once for
> the option to appear.

#### Step 3 — Register your app ID and get a provisioning profile

Apple requires every app installed on a physical device to be signed with a
provisioning profile tied to your developer account. Run:

```bash
mix mob.provision
```

This generates a small Xcode project stub, uses it to register your bundle ID with
Apple, and downloads a development provisioning profile — all from the command line.
You won't need to build or launch anything in Xcode.

> **If `mix mob.provision` fails:** open Xcode, select your phone from the device
> picker at the top, and wait for it to finish "Preparing device for development".
> Then re-run `mix mob.provision`.

#### Deploy

```bash
mix mob.deploy --native --ios
```

Mob auto-detects the connected phone. The app will appear on your home screen.

If the profile expires (free accounts: every 7 days, paid Developer Program: 1 year),
re-run `mix mob.provision` then deploy again.

---

## Android only

### What you need

- Elixir 1.18 or later with Hex: `mix local.hex`
- `mob_new` installed: `mix archive.install hex mob_new`
- Java 17–21 (`brew install --cask temurin` on macOS)
- Android Studio (includes the SDK and `adb`)

For a **physical Android device**: enable Developer Options and USB Debugging on the
device, then connect via USB and accept the authorization prompt.

### Create a project

```bash
mix mob.new my_app
cd my_app
mix mob.install
```

`mix mob.install` downloads the pre-built OTP runtime for Android and writes your
`mob.exs` and `android/local.properties`.

### Verify your environment

```bash
mix mob.doctor
```

Fix any failures before continuing. See [Troubleshooting](troubleshooting.md) if needed.

### Run on an emulator

Start an AVD from Android Studio → Device Manager, then:

```bash
mix mob.deploy --native --android
```

This builds the APK, installs it on the emulator, and pushes your BEAM files.
Subsequent deploys without `--native` push only changed `.beam` files:

```bash
mix mob.deploy --android
```

### Run on a physical Android device

There are two one-time steps before your first deploy.

#### Step 1 — Enable Developer Mode on the phone

Android hides developer options until you unlock them.

1. Open **Settings → About phone**
   - On Samsung: **Settings → About phone → Software information**
2. Find **Build number** and tap it **7 times** in quick succession
3. You'll see: *"You are now a developer!"*
4. Go back to **Settings** — a new **Developer options** entry has appeared
5. Open **Developer options** and turn on **USB debugging**

#### Step 2 — Connect via USB and set the mode

Plug in the USB cable. On the phone:

- A prompt appears: **"Allow USB debugging?"** — tap **Allow**
  (tick "Always allow from this computer" so you're not asked every time)
- Pull down the notification shade and tap the USB connection notification
- Select **File Transfer** (sometimes labelled "MTP") — not "Charging only"

Verify the connection:

```bash
adb devices
```

You should see your device listed as `device` (not `unauthorized` or `offline`).
If it shows `unauthorized`, check for a missed dialog on the phone screen.

#### Deploy

```bash
mix mob.deploy --native --android
```

Mob detects connected devices automatically. If you have more than one, use
`mix mob.devices` to find the serial ID and `--device <id>` to target it.

---

## Both platforms

### What you need

Everything from the iOS and Android sections above — but you don't need a physical
device for both. Mix and match whatever you actually have:

| Setup | What to do |
|-------|-----------|
| iOS Simulator + Android emulator | Nothing extra — just deploy |
| Physical iPhone + Android emulator | Set up iPhone (trust + Developer Mode + `mix mob.provision`) |
| iOS Simulator + physical Android | Set up Android (Developer Mode + USB debugging + File Transfer) |
| Physical iPhone + physical Android | Set up both phones, then `mix mob.provision` for iOS |

### Create a project

```bash
mix mob.new my_app
cd my_app
mix mob.install
```

### Verify your environment

```bash
mix mob.doctor
```

### Deploy to everything you have connected

```bash
mix mob.deploy --native
```

Without `--ios` or `--android`, Mob targets all connected simulators, emulators, and
physical devices at once — whatever is available. On macOS it includes both platforms;
on Linux/Windows it deploys Android only. You don't need to tell it what you have.

### If you have a physical iPhone (one-time setup)

Before your first deploy to a physical iPhone, register your app with Apple:

```bash
mix mob.provision
```

Then deploy normally — Mob auto-detects the phone alongside any running simulators
or emulators and pushes to all of them in one command:

```bash
mix mob.deploy --native
```

If you only want to target the phone and skip the simulators for a deploy:

```bash
mix mob.deploy --native --ios
```

### Targeting one device at a time

Use `mix mob.devices` to see what's connected and their IDs, then `--device <id>` to
target a specific one — useful when you have multiple physical devices or want to
isolate a deploy while keeping others running.

---

## LiveView projects

Instead of writing screens in Elixir with the `~MOB` sigil, you can run a full
Phoenix LiveView app inside a native WebView. The native shell handles device APIs
and distribution; your UI is a regular Phoenix web app.

### Extra prerequisite

You need the `phx_new` archive in addition to `mob_new`:

```bash
mix archive.install hex phx_new
```

### Create a LiveView project

Pass `--liveview` to `mix mob.new`:

```bash
mix mob.new my_app --liveview
cd my_app
mix mob.install
```

This calls `mix phx.new` under the hood, then patches the generated project:
adds the Mob bridge hook to `app.js`, inserts the `mob-bridge` element in
`root.html.heex`, adds `Mob.App` to the supervision tree, and writes a
`mob.exs` with `liveview_port: 4000`.

### Extra steps before the first deploy

**1. Set up the database**

```bash
mix ecto.create && mix ecto.migrate
```

**2. Run the Phoenix server once**

This downloads JS/CSS dependencies and compiles assets. Skip this and the
WebView will load a blank screen — the asset pipeline hasn't run yet.

```bash
mix phx.server
```

Open `http://localhost:4000` to confirm it loads, then stop the server (`Ctrl-C`).

**3. Deploy**

```bash
mix mob.deploy --native
```

The native app starts your Phoenix server at `http://127.0.0.1:4000` and loads
it in a WebView. The LiveView bridge (`window.mob.send`) routes through
`pushEvent` so server-side LiveView events reach the native layer.

### Day-to-day development

The workflow is the same as a native project — push changed BEAMs, restart, or
watch for file changes:

```bash
mix mob.deploy    # push BEAMs + restart (Phoenix server restarts inside the app)
mix mob.watch     # auto-push on file save
```

Phoenix code changes (templates, LiveViews) are picked up automatically when the
BEAM restarts. Asset changes (`app.js`, CSS) require running `mix assets.build`
locally first, since the device runs your compiled assets, not the dev pipeline.

---

## After the first deploy

These commands work the same regardless of platform.

### Connect a live IEx session

```bash
mix mob.connect
```

Tunnels Erlang distribution and drops you into an IEx session connected to the running
BEAM on the device. You can inspect state, call functions, and push code live.

```elixir
Node.list()
#=> [:"my_app_ios@127.0.0.1"]

Mob.Test.assigns(:"my_app_ios@127.0.0.1")
#=> %{count: 0, safe_area: %{top: 62.0, ...}}
```

### Hot-push a code change

Edit a module, then push the new bytecode without restarting:

```bash
mix mob.push
```

Changed `.beam` files are loaded directly into the running BEAM via RPC — no restart,
no state loss. The screen updates immediately.

### Auto-push on save

```bash
mix mob.watch
```

Watches for file changes and runs `mob.push` automatically. Combine with
`mix mob.connect` to keep an IEx session open alongside.

---

## Deployment reference

| Command | Restarts? | Requires dist? | What it does |
|---------|:---------:|:--------------:|---|
| `mix mob.deploy --native` | Yes | No | Build native binary + install + push BEAMs |
| `mix mob.deploy` | Yes | No | Push BEAMs + restart (no native rebuild) |
| `mix mob.push` | No | **Yes** | Hot-push changed BEAMs via RPC |
| `mix mob.watch` | No | **Yes** | `mob.push` on every file save |
| `nl(MyApp.Screen)` in IEx | No | **Yes** | Hot-push a single module |

**Requires dist** means Erlang distribution must be active. Run `mix mob.connect` first,
or use the dashboard (`mix mob.server`) which sets it up automatically.

### Which command should I use?

- **First time, or after changing Swift/Kotlin/C?** → `mix mob.deploy --native`
- **Changed Elixir, want a clean restart?** → `mix mob.deploy`
- **Changed Elixir, want to keep app state?** → `mix mob.push`
- **Want changes pushed automatically while editing?** → `mix mob.watch`

---

## Your first screen

```elixir
defmodule MyApp.HomeScreen do
  use Mob.Screen

  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :count, 0)}
  end

  def render(assigns) do
    ~MOB"""
    <Column padding={24} gap={16}>
      <Text text={"Count: #{assigns.count}"} text_size={:xl} />
      <Button text="Tap me" on_tap={tap(:increment)} />
    </Column>
    """
  end

  def handle_info({:tap, :increment}, socket) do
    {:noreply, Mob.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
```

`mount/3` initialises assigns. `render/1` returns the component tree via the `~MOB`
sigil. `handle_info/2` updates state in response to user events. After each update,
the framework calls `render/1` again and pushes the diff to the native layer.

---

## Next steps

- [Screen Lifecycle](screen_lifecycle.md) — mount, render, handle_event, handle_info
- [Components](components.md) — full component reference
- [Navigation](navigation.md) — stack, tab bar, drawer, push/pop
- [Theming](theming.md) — color tokens, named themes, runtime switching
- [Data & Persistence](data.md) — `Mob.State` for preferences, Ecto + SQLite for structured data
- [Device Capabilities](device_capabilities.md) — camera, location, haptics, notifications
- [Testing](testing.md) — unit tests and live device inspection
- [Troubleshooting](troubleshooting.md) — if something isn't working, start here
