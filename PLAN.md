# Mob — Build Plan

> A mobile framework for Elixir that runs the BEAM on-device.
> Last updated: 2026-04-04

---

## Session Recovery

If this session is lost, key context:

- **POC lives at:** `~/code/beam-android-test/BeamHello` (Android) and `~/code/beam-ios-test` (iOS)
- **POC status:** Working end-to-end on Android emulator + real Moto G phone. Counter + 50-item scroll list with like buttons. Touch events round-trip through BEAM.
- **Architecture proven:** BEAM embedded in Android APK → NIFs make JNI calls → BeamUIBridge dispatches to UI thread via CountDownLatch → views created on UI thread, refs returned as Erlang resources.
- **Key bug fixed:** `enif_get_int` fails for ARGB values > 0x7FFFFFFF. Use `enif_get_long` for color params.
- **Boot times:** Moto G cold 984ms (Erlang + Elixir + 150 Views), emulator ~300ms warm.
- **mob library:** `~/code/mob` — Mix project, TDD
- **mob_demo:** `~/code/mob_demo` — Android app + Elixir screens that exercise the library

---

## Architecture Decision: NIF Model (not IPC)

The plan doc proposed JSON/ETF over stdin/stdout IPC. We are **not doing that**. The POC proves NIFs work better:

- Direct JNI calls from BEAM scheduler threads — no serialization, no extra processes
- UI thread dispatch via CountDownLatch gives synchronous semantics from Elixir's perspective
- Zero IPC overhead — function call, not message passing
- Already working in production on real hardware

**NIF layer (C):** `mob_nif.c` — the bridge. Compiled into the app `.so`. Calls `MobBridge.java` (Android) / `MobBridge.swift` (iOS future).

**Elixir layer:** Pure Elixir. `Mob.Screen`, `Mob.Component`, `Mob.Socket` etc. Calls `:mob_nif` directly.

---

## Repository Layout

```
~/code/mob/                        # The library (this repo, Mix project)
├── lib/mob/
│   ├── screen.ex                  # Mob.Screen behaviour + __using__ macro
│   ├── component.ex               # Mob.Component behaviour + __using__ macro
│   ├── socket.ex                  # Mob.Socket struct + assign/2, assign/3
│   ├── renderer.ex                # Renders component tree → NIF calls
│   ├── registry.ex                # Maps component names → NIF constructors
│   └── node.ex                    # BEAM node config + startup helpers
├── lib/mob.ex                     # Top-level convenience API
├── test/mob/
│   ├── screen_test.exs
│   ├── component_test.exs
│   ├── socket_test.exs
│   ├── renderer_test.exs
│   └── registry_test.exs
├── PLAN.md                        # This file
└── mix.exs

~/code/mob_demo/                   # The demo Android app
├── lib/
│   ├── hello_screen.ex            # Iteration 1: static hello world
│   ├── counter_screen.ex          # Iteration 2: counter with state
│   ├── list_screen.ex             # Iteration 3: scroll + like buttons
│   ├── nav_screen.ex              # Iteration 4: multi-screen navigation
│   └── kitchen_sink_screen.ex    # Full component showcase
├── BeamHello/                     # Android Studio project
│   └── app/src/main/
│       ├── jni/
│       │   ├── mob_nif.c          # Renamed/refactored from android_nif.c
│       │   ├── beam_jni.c         # JNI entry points (unchanged)
│       │   ├── driver_tab_android.c
│       │   └── CMakeLists.txt
│       └── java/com/mob/demo/
│           ├── MainActivity.java
│           ├── MobBridge.java     # Renamed from BeamUIBridge
│           └── MobTapListener.java
└── PLAN.md                        # Demo-specific notes
```

---

## Iterative Build Plan

Each iteration has:
1. TDD tests in `mob/` written first
2. Implementation to pass tests
3. Demo screen in `mob_demo/` exercising the feature
4. Screenshot/logcat evidence it works on device

---

### Iteration 1 — Mob.Socket + Mob.Screen skeleton ✅ planned

**Goal:** Define the core data structures and behaviour contracts. Nothing renders yet — just the Elixir shape.

**TDD (mob/):**
- `Mob.Socket` struct: `%{assigns: %{}, __mob__: %{screen: module, platform: atom}}`
- `socket |> assign(:count, 0)` returns updated socket
- `socket |> assign(count: 0, name: "test")` bulk assign
- `Mob.Screen` behaviour defines: `mount/3`, `render/1`, `handle_event/3`, `handle_info/2`, `terminate/2`
- `use Mob.Screen` injects default implementations (all no-ops that raise if not overridden except `terminate`)

**Demo screen:** None yet — iteration is library-only.

---

### Iteration 2 — Mob.Registry + component tree ✅ planned

**Goal:** Component names → NIF calls. Mob.Registry maps `:column`, `:button`, etc. to platform-specific constructors. The renderer walks a component tree description and makes NIF calls.

**TDD (mob/):**
- `Mob.Registry.register(:column, android: :mob_nif, :create_column, [])`
- `Mob.Registry.lookup(:column, :android)` → `{:mob_nif, :create_column, []}`
- `Mob.Registry.lookup(:unknown, :android)` → `{:error, :not_found}`
- Renderer: given `%{type: :column, children: [...], props: %{}}`, calls NIF and returns view ref
- Renderer: given `%{type: :text, props: %{text: "hello"}}`, creates label and returns ref

**Demo screen:** None yet.

---

### Iteration 3 — Hello World screen on device ✅ planned

**Goal:** First end-to-end screen. `Mob.Screen` `mount/3` + `render/1` lifecycle drives a static "Hello, Mob!" on the real device.

**What changes in the Android project:**
- Rename `BeamUIBridge` → `MobBridge`, `BeamTapListener` → `MobTapListener`, `android_nif.c` → `mob_nif.c`
- `hello_world.erl` → calls `MobDemoApp` (Elixir) which starts `HelloScreen`
- `HelloScreen` uses `Mob.Screen`, renders a column with a text label

**TDD (mob/):**
- `HelloScreen.mount(%{}, %{}, socket)` → `{:ok, socket}`
- `HelloScreen.render(assigns)` → returns component tree map
- Renderer walks the tree and calls NIFs

**Demo screen:** `hello_screen.ex`
```elixir
defmodule HelloScreen do
  use Mob.Screen

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :greeting, "Hello, Mob!")}
  end

  def render(assigns) do
    ~M"""
    <.column padding={16}>
      <.text size={24}><%= @greeting %></.text>
    </.column>
    """
  end
end
```

---

### Iteration 4 — handle_event + counter screen ✅ planned

**Goal:** Touch events delivered to `handle_event/3`, state updates re-render the screen.

**TDD (mob/):**
- Event dispatch: `Mob.Screen.dispatch(pid, "increment", %{})` sends `{:mob_event, "increment", %{}}` to screen process
- `handle_event("increment", %{}, socket)` → `{:noreply, assign(socket, :count, socket.assigns.count + 1)}`
- After event, renderer diffs old tree vs new tree → only calls `set_text` NIF, not full rebuild

**Demo screen:** `counter_screen.ex` (mirrors existing DemoApp counter but via Mob.Screen lifecycle)

---

### Iteration 5 — Scroll list + lazy rendering ✅ planned

**Goal:** Scroll view with many items. Prove no performance cliff at 50, 200, 500 items.

**TDD (mob/):**
- `<.scroll>` component renders inner list via `:create_scroll` + child NIFs
- `<.lazy_list items={@items} key={:id}>` renders only visible items (future — just `scroll` for now)

**Demo screen:** `list_screen.ex` — 200-item list with toggleable like buttons. Measure scroll FPS.

---

### Iteration 6 — Navigation ✅ planned

**Goal:** Push/pop screens. Android back button handled.

**TDD (mob/):**
- `Mob.Router.push(CounterScreen)` → sends nav event to Android client
- `Mob.Router.pop()` → back
- Nav stack state in `Mob.Socket.__mob__.nav_stack`

**Demo screen:** `nav_screen.ex` — top-level screen with buttons that push counter and list screens.

---

### Iteration 7 — Full kitchen sink ✅ planned

**Goal:** Every component in the vocabulary exercised in one app.

Components: `column`, `row`, `stack`, `scroll`, `text`, `button`, `text_field`, `toggle`, `slider`, `divider`, `spacer`, `progress`, `image`.

**Demo screen:** `kitchen_sink_screen.ex`

---

## Component Vocabulary (Phase 1 Android)

| Mob tag | NIF call | Android View | Notes |
|---|---|---|---|
| `<.column>` | `create_column/0` | `LinearLayout(VERTICAL)` | |
| `<.row>` | `create_row/0` | `LinearLayout(HORIZONTAL)` | |
| `<.text>` | `create_label/1` | `TextView` | |
| `<.button>` | `create_button/1` | `Button` | |
| `<.scroll>` | `create_scroll/0` | `ScrollView` + inner `LinearLayout` | |
| `<.text_field>` | `create_text_field/1` | `EditText` | Iteration 5+ |
| `<.toggle>` | `create_toggle/1` | `Switch` | Iteration 5+ |
| `<.slider>` | `create_slider/3` | `SeekBar` | Iteration 6+ |
| `<.divider>` | `create_divider/0` | 1dp `View` with background | |
| `<.spacer>` | `create_spacer/0` | `View` with weight | |
| `<.image>` | `create_image/1` | `ImageView` | Iteration 6+ |
| `<.progress>` | `create_progress/0` | `ProgressBar` | Iteration 6+ |

---

## NIF Function Signatures (mob_nif.c)

All unchanged from POC except renamed module from `uikit_nif` → `mob_nif`.

```c
// Creation — return {:ok, view_ref}
create_column/0
create_row/0
create_label/1       // text :: binary
create_button/1      // text :: binary
create_scroll/0      // returns scroll view; inner layout via get_tag

// Tree
add_child/2          // parent :: view_ref, child :: view_ref
remove_child/1       // child :: view_ref
set_root/1           // view :: view_ref

// Mutation
set_text/2           // view, text :: binary
set_text_size/2      // view, sp :: float
set_text_color/2     // view, argb :: long   ← was int, fixed
set_background_color/2 // view, argb :: long ← was int, fixed
set_padding/2        // view, dp :: int

// Events
on_tap/2             // view, pid :: pid
```

---

## Mob.Socket

```elixir
defmodule Mob.Socket do
  defstruct [
    assigns: %{},
    __mob__: %{
      screen: nil,
      platform: :android,
      root_view: nil,
      view_tree: %{},      # ref → %{type, props, children}
      nav_stack: []
    }
  ]
end
```

---

## Mob.Screen Behaviour

```elixir
defmodule Mob.Screen do
  @callback mount(params :: map, session :: map, socket :: Mob.Socket.t) ::
    {:ok, Mob.Socket.t} | {:error, reason :: term}

  @callback render(assigns :: map) :: Mob.ComponentTree.t

  @callback handle_event(event :: String.t, params :: map, socket :: Mob.Socket.t) ::
    {:noreply, Mob.Socket.t} | {:reply, map, Mob.Socket.t}

  @callback handle_info(message :: term, socket :: Mob.Socket.t) ::
    {:noreply, Mob.Socket.t}

  @callback terminate(reason :: term, socket :: Mob.Socket.t) :: term

  # Optional lifecycle
  @callback on_focus(socket :: Mob.Socket.t) :: {:noreply, Mob.Socket.t}
  @callback on_blur(socket :: Mob.Socket.t) :: {:noreply, Mob.Socket.t}
  @callback on_foreground(socket :: Mob.Socket.t) :: {:noreply, Mob.Socket.t}
  @callback on_background(socket :: Mob.Socket.t) :: {:noreply, Mob.Socket.t}

  @optional_callbacks [
    handle_event: 3, handle_info: 2, terminate: 2,
    on_focus: 1, on_blur: 1, on_foreground: 1, on_background: 1
  ]
end
```

---

## Key Technical Constraints (learned from POC)

1. **Color values must use `enif_get_long`** — ARGB white is 0xFFFFFFFF = 4294967295, overflows `enif_get_int`.
2. **FindClass on non-main threads fails** — cache all class refs in `JNI_OnLoad` via `mob_ui_cache_class(env)`.
3. **CountDownLatch must have try/finally** — if the Runnable throws, latch never fires → deadlock. Always `finally { latch.countDown(); }`.
4. **`enif_keep_resource`** when registering tap listener — Java holds raw ptr, GC must not free resource.
5. **`-Wl,--allow-multiple-definition`** needed before `--whole-archive` for libbeam.a.
6. **`DED_LDFLAGS="-shared"`** not `"-r"` — Android lld rejects `-r` with `-ldl`.
7. **`application:start(compiler)`** before `application:start(elixir)` — Elixir depends on it.
8. **Deploy beam files via `run-as`** on non-rooted devices: push to `/data/local/tmp/` then `run-as com.beam.hello cp`.

---

## mob_demo Android Project

**Derived from BeamHello POC.** Key renames:
- `BeamUIBridge` → `MobBridge`
- `BeamTapListener` → `MobTapListener`
- `android_nif.c` → `mob_nif.c`
- Package: `com.mob.demo`
- `-s hello_world start` → `-s mob_demo start`

**mob_demo entry point (Erlang):**
```erlang
-module(mob_demo).
-export([start/0]).
start() ->
    ok = application:start(compiler),
    ok = application:start(elixir),
    ok = application:start(logger),
    'Elixir.MobDemo.App':start(),
    timer:sleep(infinity).
```

**MobDemo.App:**
```elixir
defmodule MobDemo.App do
  def start do
    # Start root screen via Mob.Screen
    Mob.Screen.start_root(MobDemo.HelloScreen)
  end
end
```

---

## What's NOT in Phase 1

- HEEx template rendering (use plain Elixir map trees first, HEEx in Phase 2)
- Jetpack Compose (sticking with Android Views — already proven, Compose migration in Phase 2)
- iOS (architecture is designed for it, implementation in Phase 2)
- `mix mob.new` generator (Phase 3)
- Distribution / clustering (works out of the box via OTP, document but don't build tooling)
- Stylesheet system (Phase 2)

---

## Immediate Next Steps

1. Write `Mob.Socket` with tests (Iteration 1)
2. Write `Mob.Screen` behaviour with tests (Iteration 1)
3. Write `Mob.Registry` with tests (Iteration 2)
4. Set up mob_demo Android project (copy+rename from BeamHello)
5. Wire HelloScreen through the stack end-to-end on device (Iteration 3)

---

## Phase 2+ Roadmap

### lazy_list API
`<.lazy_list>` needs `on_end_reached` event (fires when user scrolls near the end, for infinite scroll) and a `threshold` prop (how many items from the end to trigger — mirrors React Native FlatList's `onEndReachedThreshold`). NIF side: listen for RecyclerView scroll state; Elixir side: `handle_event("end_reached", %{}, socket)`.

### Push Notifications
`mob_push` package. FCM (Android) / APNs (iOS). Registration token surfaced via `handle_info({:notification, payload}, socket)`. App requests permission via `Mob.Permissions.request(:notifications, socket)` (see Permissions below). Server-side sending out of scope for mob library — just receive and route.

### Permissions System
`Mob.Permissions.request(:camera | :location | :microphone | :notifications, socket)` — triggers OS dialog, result delivered as `handle_info({:permission_result, :camera, :granted | :denied | :not_determined}, socket)`. `Mob.Permissions.status(:location)` → synchronous check. Android: `ActivityCompat.requestPermissions`; iOS: `AVCaptureDevice.requestAccess` etc.

### Offline / Local Storage
SQLite via NIF (`exqlite` or a thin mob-specific wrapper). Blessed pattern: one `Mob.Repo` per app, schema defined in Elixir, migrations run on app start. Keeps it familiar for Phoenix devs. Key constraint: WAL mode on by default; single writer, multiple readers OK on device.

### App Store / Play Store Build Pipeline
`mix mob.release --platform android|ios` — triggers Gradle/Xcode build, signs the artifact, outputs `.aab` / `.ipa`. Fastlane integration for upload. Separate `mix mob.release.upload --track internal` for Play/TestFlight. Needs signing config in `mob.exs` (keystore path, provisioning profile).

### Accessibility
TalkBack (Android) / VoiceOver (iOS) support. Prop: `accessible_label` on any component (maps to `contentDescription` / `accessibilityLabel`). `accessible_hint` for secondary description. `accessible_role` (button, image, header, etc.) maps to `AccessibilityNodeInfoCompat.setRoleDescription` / `UIAccessibilityTraits`. Goal: zero-config for text components (label text is used automatically); explicit opt-in for images and custom components.

### Mob.DevServer (AI + Playwright integration)

Starts alongside `mix mob.dev`. Exposes the running app to external tools — Playwright, Tidewave, Claude — without browser-based Android emulation.

**Key insight:** `Mob.Screen` already holds the full render tree in `socket.__mob__.view_tree`. The native views (Android Views / UIKit) are just the rendered output of it. We never need to reverse-engineer the native side — the Elixir tree is always in sync and is the canonical representation.

`Mob.DevServer` serializes that tree as HTML:
```
:column  →  <div style="display:flex; flex-direction:column">
:row     →  <div style="display:flex; flex-direction:row">
:text    →  <span>
:button  →  <button>
```

Served as a Phoenix LiveView page that updates in real time as app state changes.

**Endpoints:**
```
GET  /            → live HTML mirror of current render tree (Playwright target)
GET  /assigns     → current screen assigns as JSON
GET  /tree        → raw component tree as JSON
GET  /screenshot  → PNG via NIF
POST /tap         → simulate a tap event
POST /event       → send any event to the running screen
WS   /live        → stream of state changes
```

**Why this beats browser-based Android:**
- Works identically for Android and iOS — one interface, one Playwright script
- Real DOM elements, not pixels — `page.click("button:has-text('Increment')")` just works
- Tidewave can read `/assigns` and `/tree` to feed structured data directly to Claude
- No heavyweight emulator; no pixel scraping; always in sync with app state

**Claude feedback loop:** Playwright screenshots + DOM + `/assigns` JSON gives Claude full visibility into the running app on any platform. Same workflow as debugging a Phoenix LiveView.

---

### Testing Story

**`Mob.ScreenTest` — unit tests, no device needed**

Pure Elixir, no emulator, no NIF calls. NIFs stubbed out; component tree returned as a plain map for assertions. API mirrors LiveView's `live/2` + `render_click`.
```elixir
test "counter increments" do
  {:ok, screen} = Mob.ScreenTest.mount(CounterScreen)
  assert screen.assigns.count == 0
  {:ok, screen} = Mob.ScreenTest.event(screen, "increment", %{})
  assert screen.assigns.count == 1
end
```

**`Mob.UITest` — integration tests against a running device**

Connects to the on-device node over Erlang distribution (same WiFi, `mac.local`). Drives the real running app — real NIFs, real platform views. No Appium, no Espresso, no XCUITest. Same API for Android and iOS.

```elixir
test "counter increments on tap" do
  {:ok, screen} = Mob.UITest.mount(device_node, CounterScreen)
  assert Mob.UITest.assigns(screen).count == 0

  Mob.UITest.tap(screen, "increment-button")
  assert Mob.UITest.assigns(screen).count == 1
  assert Mob.UITest.text(screen, "counter-label") == "Count: 1"
end
```

Screenshot support via a NIF that returns a PNG binary — useful for visual regression tests. Simulator/emulator can also use platform tools (`xcrun simctl io`, `adb`) when available.

**Remote inspection (free once distribution is set up):**
- `:observer.start()` on Mac shows on-device process tree, memory, message queues
- `:dbg` / `:recon` for function call and message tracing on-device from Mac IEx
- `:sys.get_state(pid)` to inspect any live GenServer

### Fonts and Assets
`mix mob.gen.assets` — copies fonts/images into the correct platform dirs (`res/font/`, `Assets.xcassets`). `<.text font="MyFont-Bold">` maps to a registered font name. Images: `<.image src={:my_logo}>` resolved from asset catalog at build time. Hash-based cache busting for OTA updates.

### Hot Deploy (Dev UX)

Two modes: dev (code lives on Mac) and release (self-contained on device).

**Dev mode — Erlang distribution + file watcher**

Device runs a minimal install: ERTS (compiled into the app binary) + OTP base apps (kernel, stdlib, elixir, logger beams — stable). All `mob` library and app screen code lives on the Mac.

Bootstrap on device dials home to the Mac node on startup. From that point the device is a display terminal — app code runs on-device via distribution, but the source of truth is the Mac.

Mac side runs `iex -S mix mob.dev`, which:
1. Starts a file watcher on `lib/` (same as Phoenix's `mix phx.server`)
2. On `.ex` change: recompiles → calls `nl(Module)` to push bytecode to all connected nodes (device included)
3. Sends a re-render signal so the running `Mob.Screen` picks up the new module

From IEx you also get the full dev loop manually:
```elixir
r(MobDemo.CounterScreen)  # recompile + load on device instantly
Node.call(:"mob_demo@device", :sys, :get_state, [MobDemo.CounterScreen])  # inspect live state
```

Device dials Mac's LAN IP directly over WiFi — no adb, no platform-specific tooling. Same mechanism works identically on Android and iOS. Bootstrap dials `mac.local` (mDNS) — works out of the box on both platforms when on the same WiFi. Zero config, survives IP changes.

Re-render hook: `Mob.Screen` implements `code_change/3` (standard OTP GenServer callback) — called automatically by OTP when the module is hot-loaded. Triggers a re-render with current assigns.

**Release mode — self-contained**

`mix mob.release --platform android|ios` bundles everything (OTP base + mob library + app beams) onto the device. No Mac connection. This is also the App Store / Play Store path.

Deploy commands:
```bash
./deploy.sh --dev      # minimal install, dials home to Mac IEx
./deploy.sh --release  # or: mix mob.release --platform android
```

### Error Boundaries
`<.error_boundary>` component with a `fallback` slot. Catches crashes in child component trees (via process links or try/rescue in renderer) and renders the fallback instead of crashing the whole screen. Configurable supervision: `:restart` (re-mount screen), `:show_fallback` (static error UI), `:propagate` (let it crash — default OTP behaviour). Useful for isolating third-party components or experimental screens.

---

## Long Term / Experimental

### Headless Mode (phone as a server)

Run BEAM as an Android Foreground Service with no UI component. The Foreground Service keeps the process at foreground priority — Android won't kill it under memory pressure. A persistent notification is required (the OS-enforced cost of the feature).

Use case: a phone running a full OTP application — GenServers, Phoenix, Ecto, PubSub — with no screen. Essentially a low-power server node you can put in a drawer. The phone's LTE/WiFi makes it reachable anywhere; OTP clustering means it can join a distributed system.

Intentionally long-term: background execution is a battery and abuse vector. Would need rate limiting, battery-aware supervision (pause work when battery is low), and clear user consent. iOS equivalent is heavily restricted by the OS and would require a declared Background Mode (audio, location, VoIP) — no general-purpose equivalent.
