# Mob — Build Plan

> A mobile framework for Elixir that runs the BEAM on-device.
> Last updated: 2026-04-14

---

## What's shipped

### Core framework
- ✅ `Mob.Socket`, `Mob.Screen`, `Mob.Component`, `Mob.Registry`, `Mob.Renderer`
- ✅ HelloScreen on Android emulator (Pixel 8) and real Moto phone (non-rooted)
- ✅ HelloScreen on iOS simulator (iPhone 17) via SwiftUI
- ✅ CounterScreen — tap → NIF → `enif_send` → `handle_event` → re-render (both platforms)
- ✅ Erlang distribution on Android (`Mob.Dist`, deferred 3s to avoid hwui mutex race)
- ✅ Erlang distribution on iOS (simulator shares Mac network stack, reads `MOB_DIST_PORT` env)
- ✅ Simultaneous Android + iOS connection — both nodes in one IEx cluster
- ✅ Battery benchmarking — Nerves tuning flags (`+sbwt none +S 1:1` etc.) adopted as production default in `mob_beam.c`
- ✅ `mob_nif:log/2` NIF + `Mob.AndroidLogger` OTP handler → Elixir Logger → mob_dev dashboard

### Toolchain (all published on Hex)
- ✅ `mix mob.new APP_NAME` — generates full Android + iOS project from templates
- ✅ `mix mob.install` — first-run: downloads pre-built OTP, generates icons, writes mob.exs
- ✅ `mix mob.deploy [--native]` — compile + push BEAMs via adb/cp; `--native` also builds APK/app
- ✅ `mix mob.push` — compile + hot-push changed modules via Erlang dist (no restart)
- ✅ `mix mob.watch` — auto-push on file save via dist
- ✅ `mix mob.watch_stop` — stops a running mob.watch process
- ✅ `mix mob.connect` — tunnel + restart + wait for nodes + IEx
- ✅ `mix mob.battery_bench` — A/B test BEAM scheduler configs with mAh measurements
- ✅ `mix mob.icon` — regenerate icons (random robot or from source image)
- ✅ Pre-built OTP tarballs on GitHub (android + ios-sim), downloaded automatically

### mob_dev server (v0.2.2)
- ✅ Device discovery (adb + xcrun simctl), live device cards
- ✅ Per-device deploy buttons (Update / First Deploy)
- ✅ Live log streaming (logcat + iOS simulator log stream)
- ✅ Log filter (App / All / per-device) + free-text filter (comma-separated terms)
- ✅ Deploy output terminal inline per device card
- ✅ Elixir Logger → dashboard (mob_nif:log/2 pipeline)
- ✅ QR code in header — encodes LAN URL for opening dashboard on phone
- ✅ `mix mob.server` — starts server, binds to 0.0.0.0:4040, prints QR in terminal

---

## Deploy model (architectural decision 2026-04-14)

See `ARCHITECTURE.md` for the full write-up. Short version:

- **`mix mob.deploy --native`** — USB required. Full push: builds APK/IPA, installs via adb/xcrun, copies BEAMs.
- **`mix mob.deploy`** — USB optional. Fast push: compiles BEAMs, saves to mob_dev server, distributes to connected nodes via Erlang dist. Falls back to adb push if no dist connection.
- **`mix mob.push` / `mix mob.watch`** — dist only. Hot-loads changed modules in place, no restart.

USB is only required for first deploy. After that, Erlang distribution is the transport for all code updates across both Android and iOS.

---

## Next up

### 1. ListScreen with scroll
**Goal:** Scroll view rendering 200 items. Prove no performance cliff.
- `<.scroll>` wrapping a list of `<.row>` / `<.text>` components
- Measure scroll FPS on real Moto phone
- Demo: `mob_demo/lib/mob_demo/list_screen.ex`

### 2. Navigation (push/pop)
**Goal:** Multi-screen apps. Android back button handled.
- `Mob.Router.push(TargetScreen)` / `Mob.Router.pop()`
- Nav stack in `Mob.Socket.__mob__.nav_stack`
- Demo: top-level screen with buttons pushing counter and list screens

### 3. `mix mob.deploy` → dist
**Goal:** Align implementation with architecture decision.
Currently `mix mob.deploy` (non-native) uses `adb push` / `cp`. Change it to compile + push via Erlang dist when a node is reachable. Keep adb push as fallback for when dist isn't up.

### 4. `mix mob.watch` in mob_dev dashboard
**Goal:** "Push on save" toggle in the web UI — same logic as `mix mob.watch` but driven from the server.
- `MobDev.Server.WatchWorker` GenServer — wraps the watch loop
- Toggle switch in dashboard header starts/stops it
- Status indicator: last push time, module count, errors

### 5. KitchenSink screen
All Phase 1 components exercised in one demo screen: `column`, `row`, `scroll`, `text`, `button`, `text_field`, `toggle`, `slider`, `divider`, `spacer`.

---

## Phase 2 roadmap

### `~MOB` sigil syntax (Iteration 3.7)
Both render paths working — sigil (familiar to LiveView devs) and tuple (composable, programmatic). Single `normalize/1` layer converts either to the internal map tree. Zero extra maintenance cost.

```elixir
def render(assigns) do
  ~MOB"""
  <.column padding={16}>
    <.text size={24}>{@greeting}</.text>
    <.button on_tap="increment">+</.button>
  </.column>
  """
end
```

### Generators (Igniter)
`mix mob.gen.screen`, `mix mob.gen.component`, `mix mob.gen.release` — using Igniter for idiomatic AST-aware code generation. Same infrastructure as `mix phx.gen.live`. AI agents use generators as the blessed path rather than writing from scratch.

### Physical device support
- **Android wireless**: already works via USB adb; wireless reconnect via dist (no extra work needed after ARCHITECTURE.md flow)
- **iOS physical**: needs `iproxy` USB tunneling (libimobiledevice) for dist port forwarding

### lazy_list
`<.lazy_list items={@items}>` — renders only visible items. `on_end_reached` event for infinite scroll. NIF side: RecyclerView scroll state listener.

### Push notifications
`mob_push` package. FCM (Android) / APNs (iOS). Registration token + `handle_info({:notification, payload}, socket)`. `Mob.Permissions.request(:notifications, socket)`.

### Offline / local storage
SQLite via NIF. `Mob.Repo` with Elixir schema + migrations on app start. WAL mode default.

### App Store / Play Store build pipeline
`mix mob.release --platform android|ios` — Gradle/Xcode build, signing, `.aab` / `.ipa` output. Fastlane for upload.

---

## Component vocabulary (Phase 1)

| Mob tag | Android View | iOS (SwiftUI) |
|---|---|---|
| `<.column>` | `LinearLayout(VERTICAL)` | `VStack` |
| `<.row>` | `LinearLayout(HORIZONTAL)` | `HStack` |
| `<.text>` | `TextView` | `Text` |
| `<.button>` | `Button` | `Button` |
| `<.scroll>` | `ScrollView` + inner `LinearLayout` | `ScrollView` |
| `<.text_field>` | `EditText` | `TextField` |
| `<.toggle>` | `Switch` | `Toggle` |
| `<.slider>` | `SeekBar` | `Slider` |
| `<.divider>` | 1dp `View` with background | `Divider` |
| `<.spacer>` | `View` with weight | `Spacer` |
| `<.image>` | `ImageView` | `Image` |
| `<.progress>` | `ProgressBar` | `ProgressView` |

---

## Key technical constraints

1. **`enif_get_long` for color params** — ARGB 0xFFFFFFFF overflows `enif_get_int`. Always use `enif_get_long`.
2. **Cache JNI class refs in `JNI_OnLoad`** — `FindClass` fails on non-main threads. `mob_ui_cache_class(env)` caches all refs upfront.
3. **CountDownLatch needs try/finally** — if the Runnable throws, latch never fires → deadlock.
4. **`enif_keep_resource` for tap listeners** — Java holds raw ptr; GC must not free the resource.
5. **Android dist deferred 3s** — starting distribution at BEAM launch races with hwui thread pool → SIGABRT. `Mob.Dist.ensure_started/1` defers `Node.start/2` by 3 seconds.
6. **ERTS helpers as `.so` files in jniLibs** — SELinux blocks `execve` from `app_data_file`; packaging as `lib*.so` gets `apk_data_file` label which allows exec.
7. **`+C` flags invalid in `erl_start` argv** — when calling `erl_start` directly (bypassing `erlexec`), all emulator flags use `-` prefix. `+C multi_time_warp` → `-C multi_time_warp`. OTP 28+ default is already `multi_time_warp`, safe to omit.
8. **iOS OTP path** — `mob_beam.m` reads from `/tmp/otp-ios-sim`; deployer prefers that path when it exists. Cache dir (`~/.mob/cache/otp-ios-sim-XXXX/`) is fallback only.
9. **`--disable-jit` for real iOS devices** — iOS enforces W^X; JIT writes+executes memory which is blocked. Simulator builds can keep JIT. Android unaffected.
10. **Android BEAM stderr → `/dev/null`** — silent `exit(1)` from ERTS arg parse errors is the symptom. Check flags carefully; use logcat wrapper to surface boot errors.

---

## Hex packages

- `mob` v0.2.0 — github.com/genericjam/mob, MIT
- `mob_dev` v0.2.2 — github.com/genericjam/mob_dev, MIT
- `mob_new` v0.1.6 — archive, `mix archive.install hex mob_new`
