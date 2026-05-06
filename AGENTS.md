# AGENTS.md — orientation for AI agents working on Dala

You're in the **dala** repo, the runtime library for the Dala dalaile framework.
Read this in full before making changes — it's the 5-minute orientation that
will keep you from re-deriving things the rest of the team has already learned
(or learned the hard way).

## What Dala is, in one paragraph

Dala lets you write iOS and Android apps in Elixir, with the BEAM running
on-device. The phone hosts an Erlang node — a real one, distribution-capable,
introspectable, hot-code-loadable. Two modes: a SwiftUI/Compose UI driven by
Elixir GenServers (Dala UI apps), or a sidecar BEAM embedded in a normal native
app to give agents and tests live access (Dala as test harness). The sidecar
mode is the long-term bet. Both modes produce a real Erlang node you can `Node.connect/1` to.

For the *why* (the BEAM-on-dalaile pitch), see `guides/why_beam.md`.

## Repo topology

Dala is three coordinated repos. **Know which one to edit before you change anything.**

| Repo | Path | What lives here | Edit when |
|---|---|---|---|
| **dala** | `~/code/dala` | Runtime library: `Dala.Screen`, `Dala.App`, `Dala.Renderer`, `Dala.Dist`, `Dala.Test`, the iOS Swift / Android Kotlin native bridges, the NIF | UI behavior, on-device runtime, native bridge changes |
| **dala_dev** | `~/code/dala_dev` | Mix tasks: `dala.deploy`, `dala.connect`, `dala.devices`, `dala.emulators`, `dala.provision`, `dala.doctor`, `dala.battery_bench_*`. Device discovery (`DalaDev.Discovery.{Android,IOS}`). Native build orchestration (`DalaDev.NativeBuild`). OTP tarball download/cache (`DalaDev.OtpDownloader`). | Build/deploy mechanics, device handling, dev tooling |
| **dala_new** | `~/code/dala_new` | Project generator. Hex archive (`mix archive.install hex dala_new`). Templates in `priv/templates/dala.new/`. Generates both native Dala UI projects and Phoenix LiveView wrappers. | Generator output for new projects |

Cross-repo changes are common — fixing one user-visible behavior often needs
the runtime patched in `dala`, the build retooled in `dala_dev`, **and** the
generator template updated in `dala_new` so newly-generated projects pick up
the fix without manual edits.

The OTP runtime tarballs (Android arm64/arm32, iOS sim, iOS device) are built
separately and uploaded to GitHub Releases — see `dala_dev/build_release.md`
and `dala_dev/scripts/release/`. Patches we apply to OTP source live at
`dala_dev/scripts/release/patches/`.

## Driving apps from your session

The default instinct — screenshots — is wrong. Dala apps run a real Erlang node
you can talk to directly. Read the BEAM, drive it, then verify visually only
when state isn't enough.

### Connect

```bash
mix dala.devices                 # list everything connected (sims, emulators, physical)
mix dala.emulators --list        # list virtual devices (running and stopped)
mix dala.connect                 # set up tunnels, start IEx attached to all running nodes
mix dala.connect --no-iex        # just print node names + tunnels (for scripting)
```

Node names are platform-specific:

```
dala_demo_ios@127.0.0.1                     # iOS simulator
dala_demo_android_<serial-suffix>@127.0.0.1  # Android (suffix from ro.serialno)
```

For iOS simulator, the sim shares the Mac's network stack — distribution Just
Works. For Android (and iOS device), `mix dala.connect` sets up `adb reverse` /
similar tunnels.

### Inspect (`Dala.Test`, BEAM-state, fast, exact — prefer this)

```elixir
node = :"dala_demo_ios@127.0.0.1"

Dala.Test.screen(node)            # which screen is showing?  → ModuleName
Dala.Test.assigns(node)           # live socket assigns        → %{...}
Dala.Test.find(node, "Submit")    # locate widget by visible text
Dala.Test.inspect(node)           # full snapshot: screen, assigns, nav stack, widget tree
```

This is faster, exact (not pixel-inferred), and works without taking a
screenshot. Use it as the default.

### Drive

```elixir
Dala.Test.tap(node, :open_text)              # tap by tag atom (the on_tap: {self(), :tag})
Dala.Test.send_message(node, {:custom, :msg}) # arbitrary handle_info
```

After a tap, call `Dala.Test.screen(node)` again to confirm navigation
happened. Call `Dala.Test.assigns(node)` to confirm state changed.

### Visual verify (MCP, slower, image-based — only when needed)

When layout/animation/rendering matters, fall back to MCP platform tools:

| iOS simulator | Android |
|---|---|
| `mcp__ios-simulator__screenshot` | `mcp__adb__dump_image` |
| `mcp__ios-simulator__ui_view` | `mcp__adb__inspect_ui` |
| `mcp__ios-simulator__ui_tap {x, y}` | `adb shell input tap` |
| `mcp__ios-simulator__ui_swipe` | `adb shell input swipe` |
| `mcp__ios-simulator__record_video` | `adb shell screenrecord` |

Use these to confirm a layout looks right, spot animation glitches, or
debug rendering. **Don't use them for state queries** — `Dala.Test.assigns/1`
is always better.

### Round-trip workflow

```
1. Edit Elixir/Swift/Kotlin code
2. mix dala.push                  # fast: BEAM-only push, no native rebuild
   mix dala.deploy --native       # slower: native rebuild needed (NIF / Swift / Kotlin change)
3. Dala.Test.screen(node)         # confirm navigation / state
4. mcp__*__screenshot            # spot-check visual (only if layout matters)
5. Dala.Test.tap(node, :button)   # drive next interaction
6. Dala.Test.assigns(node)        # confirm state updated
7. repeat
```

Full workflow detail: `guides/agentic_coding.md`.

## Pre-empt-failure rules — read before you touch anything

These are the things we've burned ourselves on. Following them isn't optional.

1. **Default arguments evaluate eagerly.** `System.get_env("ROOTDIR", Path.expand("~/..."))`
   evaluates `Path.expand` *every call*, regardless of whether `ROOTDIR` is set.
   `Path.expand("~/...")` calls `System.user_home!()` which raises on Android
   (no `HOME` env var). Use `case System.get_env(...)` or `||` instead. Burned us
   once — see commit `d77932e`.

2. **Don't silently swallow `Dala.Screen.start_root` errors.** It returns
   `{:ok, pid}` or `{:error, reason}` and crashes from inside `init` are reported
   via `{:error, ...}`. If you don't pattern-match, the screen never renders and
   the app sits on the "Starting BEAM…" splash forever. The on_start callback
   should `{:ok, _} = Dala.Screen.start_root(...)` so failures crash loudly.

3. **TDD discipline in dala_dev.** Every new public function gets a test.
   `dala_dev/CLAUDE.md` makes this explicit. Don't bypass — the tests are how we
   catch the multi-step regressions like the iOS-device deploy chain.

4. **Format + credo before commit.** `mix format && mix credo --strict` from the
   relevant repo, every time. Both are clean across the codebase today; don't
   regress them.

5. **Multi-repo changes batch together.** A user-visible fix in dala often needs
   matching changes in dala_dev (build) and dala_new (template). Bumping versions
   without coordination produces ghost regressions. Check all three before
   declaring done.

6. **iOS device sandbox blocks `fork()`.** The BEAM's `forker_start` and EPMD's
   `run_daemon` both call fork; both are patched in our OTP cross-compile.
   Patches at `dala_dev/scripts/release/patches/`. Don't undo them.

7. **iOS sim and iOS device are different build paths.** Sim → `ios/build.sh`
   (`build_ios/1` in NativeBuild). Device → `ios/build_device.sh`
   (`build_ios_physical/2`). When `--device <udid>` is passed, dala_dev resolves
   it via `IOS.list_devices/0` to know which path to take. Don't shortcut.

8. **LV port 4200 is global per device.** Two installed Dala LV apps + one
   running = the second can't bind. Workaround for now: force-stop the squatter.
   Real fix tracked in `issues.md` #4 (hash bundle id into port).

9. **Compile-time `~r//` literals are unsafe on OTP 28.** They bake a
   `:re_exported_pattern` and call `:re.import/1` at runtime; OTP 28.0 removed
   that function. Use `Regex.compile!("...", "flags")` to compile at runtime.
   71 literals across dala_dev were swept in 0.3.17.

10. **`:dala_nif.log/1` for early startup logging, `Logger` after Dala.App.start.**
    `Dala.NativeLogger.install()` runs as part of `Dala.App.start` and reroutes
    `Logger` to NSLog/logcat. Before that point (steps 1–4 in the Erlang
    bootstrap), `Logger` output goes to stderr and is invisible. Use
    `:dala_nif.log("message")` for diagnostics during early init.

### 11. **UI render path: Elixir → Binary Protocol → Rust NIF → ObjC → SwiftUI.**
    The render pipeline now uses a **custom binary protocol** instead of JSON:
    - `Dala.Renderer.render/4` encodes `Dala.Node` trees to compact binary
    - `Dala.Renderer.encode_tree/1` handles full tree encoding
    - `Dala.Renderer.encode_frame/1` handles incremental patch encoding
    - `Dala.Native.set_root_binary/1` NIF receives binary data (replaces `set_root/1`)
    - Binary format: `[u16 version][u16 flags][u64 node_count] + nodes`
    - Patches: `[u16 version=1][u16 patch_count] + opcodes`
    - Zero-copy at boundary: Rustler's `Binary<'a>` maps directly to BEAM off-heap binaries
    - See `Dala.Renderer` module docs for full binary protocol spec.

12. **Skip renders when nothing changed (Strategy 1).**
    `Dala.Socket.assign/3` now tracks changed keys in `__dala__.changed`.
    `Dala.Socket` struct properly initializes `changed` in the struct definition
    (not just in `new/2`) so pattern matching always works.
    `Dala.Screen.do_render/3` skips the render if no assigns changed
    and no navigation occurred. This avoids unnecessary JSON encoding +
    SwiftUI diffing for events that don't affect the UI.
    To force a render, use `Dala.Socket.changed?/2` to check if specific
    keys changed, or rely on navigation (push/pop/reset) which always renders.
    **Fixed 2025:** `do_render/3` now clears `changed` even when skipping
    render, preventing stale change tracking.

13. **Struct fields used in guards/pattern-matching must be initialized.**
    If a struct defines a field but doesn't set a default, code that
    accesses it with `socket.__dala__.changed` (instead of `[:changed]`)
    will fail when the field is missing. Always initialize all fields
    in the struct definition, not just in constructor functions.
    Burned us in `Dala.Socket` where `:changed` was only set in `new/2`.

## 14. **Zero-config ML on iOS/Android.**
    `Dala.ML.EMLX.setup/0` auto-configures EMLX for the platform:
    - iOS device: Metal GPU, JIT disabled (W^X policy)
    - iOS simulator: Metal GPU, JIT enabled
    - Non-iOS: no-op, falls back to Nx.BinaryBackend
    No manual `config :nx, ...` or `config :emlx, ...` needed!
    See `examples/ml_app/` for a ready-to-run YOLO detection app.

## 15. **WebView interact API for programmatic control.**
    `Dala.WebView.interact/2` provides a high-level API for driving WebView
    content from Elixir, similar to `Dala.Test` but for production use.
    
    Available actions:
    - `{:tap, selector}` - Tap an element by CSS selector
    - `{:type, selector, text}` - Type text into input fields
    - `{:clear, selector}` - Clear input fields
    - `{:eval, js_code}` - Evaluate JS and get result via `handle_info({:webview, :eval_result, ...})`
    - `{:scroll, selector, dx, dy}` - Scroll elements programmatically
    - `{:wait, selector, timeout_ms}` - Wait for elements to appear
    
    Results arrive as `handle_info({:webview, :interact_result, %{"action" => ..., "success" => ...}}, socket)`.
    
    Also added: `navigate/2`, `reload/1`, `stop_loading/1`, `go_forward/1`
    for complete WebView navigation control.

## 16. **Spark DSL for declarative screens.**
    Dala supports a Spark DSL for defining screens declaratively. The DSL mirrors
    `Dala.UI` one-to-one — every component and prop available in `Dala.UI` has
    a DSL equivalent.

    ```elixir
    defmodule MyApp.CounterScreen do
      use Dala.Spark.Dsl

      attributes do
        attribute :count, :integer, default: 0
      end

      screen do
        name :counter
        column do
          gap :space_sm
          text "Count: @count"
          button "Increment", on_tap: :increment
        end
      end

      def handle_event(:increment, _params, socket) do
        {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
      end
    end
    ```

    Features:
    - **@ref syntax**: Use `@count` in strings to reference assigns (processed at compile time)
    - **Auto-generated mount/3**: Initializes attributes with defaults; always generated
    - **Compile-time verifiers**: Validates prop types and handler references
    - **Layout containers**: column, row, box, scroll, modal, pressable, safe_area (with nested children)
    - **Leaf components**: text, button, icon, divider, spacer, text_field, toggle, slider,
      switch, image, video, activity_indicator, progress_bar, status_bar, refresh_control,
      webview, camera_preview, native_view, tab_bar, list
    - **Container props go inside do blocks**: `column do padding :space_md; gap :space_sm; ... end`
    - **Leaf props as keyword args**: `text "Hello", text_size: :xl`

    The extension module (`Dala.Spark.Dsl`) is both a Spark extension and a DSL
    module (`use Spark.Dsl, default_extensions: [extensions: __MODULE__]`).
    This means `use Dala.Spark.Dsl` sets up the full Spark DSL on the user module.

    See `guides/spark_dsl.md` for full documentation.

## 17. **Dala.App screens/1 helper.**
    Use `screens/1` in your app's `navigation/1` to register screen modules:
    
    ```elixir
    def navigation(_) do
      screens([MyApp.HomeScreen, MyApp.SettingsScreen])
      stack(:home, root: MyApp.HomeScreen)
    end
    ```
    
    This validates at compile time that the modules are valid Dala.Screen modules.

## 18. **Incremental rendering with diff engine.**
    Dala now supports patch-based UI updates instead of full tree re-renders.
    
    **Architecture:**
    - UI trees use `Dala.Node` struct with stable `:id` field for identity
    - `Dala.Diff.diff(old, new)` compares two `Dala.Node` trees and produces patches
    - `Dala.Renderer.render_patches/5` sends only the patches to native (when supported)
    - `Dala.Screen` stores the previous tree (as `Dala.Node`) in `__dala__.last_tree`
    
    **Patch types:**
    - `{:replace, id, node}` — Replace entire node
    - `{:update_props, id, props}` — Update props on existing node
    - `{:insert, parent_id, index, node}` — Insert new node
    - `{:remove, id}` — Remove node
    
    **Node identity:**
    - `Dala.Node` requires `:id` field for proper reconciliation
    - `Dala.Node.from_map/2` converts maps to structs, generating IDs if needed
    - Explicit IDs are recommended for dynamic lists
    
    **Fallback:** If native doesn't support `apply_patches/1`, falls back to full render.
    
    **Testing:** `Dala.Diff` has comprehensive tests in `test/dala/diff_test.exs`.

## 19. **Bluetooth/WiFi setup mix task.**
    `mix dala.setup_bluetooth_wifi` simplifies Bluetooth and WiFi permissions setup.
    
    **Features:**
    - Detects platform (iOS, Android, or both)
    - Runs platform-specific setup scripts if available (`scripts/ios_setup.sh`, `scripts/android_setup.sh`)
    - Falls back to manual setup with clear instructions
    - Verifies setup by checking files and permissions
    - Idempotent (safe to run multiple times)
    
    **Options:**
    - `--platform ios|android|all` (default: all)
    - `--no-color` to disable colored output
    
    **Runtime helpers:** `Dala.Setup` module provides `check_bluetooth/0`, `check_wifi/0`,
    `ensure_bluetooth_permissions/1`, `ensure_wifi_permissions/1`, and `diagnostic/0`.
    Call from app startup or screens to verify permissions at runtime.

## Where to look

| Question | File |
|---|---|
| Round-trip workflow + MCP setup | `guides/agentic_coding.md` |
| System architecture / native cocoon model | `CLAUDE.md` (top half), `ARCHITECTURE.md` |
| "I hit error X — has this happened before?" | `common_fixes.md` |
| "Does this user-facing setup issue ring a bell?" | `user_issues.md` |
| Open known issues with diagnoses + fixes | `issues.md` |
| Speculative ideas, longer-term plans | `future_developments.md`, `wire_tap.md`, `PLAN.md` |
| Per-feature deep dives (events, navigation, theming, ...) | `guides/*.md` |
| Render engine deep dive (Elixir → native data transfer) | `guides/render_engine.md` |
| UI design patterns (sigil vs DSL style) | `guides/ui_design.md` |
| Architecture decisions (one ADR per cross-cutting decision) | `docs/decisions/` |
| iOS device deployment (provisioning, build chain, gotchas) | `guides/ios_physical_device.md` |
| iOS ML support (Nx, Axon, EMLX) | `guides/ios_ml_support.md`, `lib/dala/ml/` |
| Bluetooth/WiFi setup and API | `docs/bluetooth_wifi_implementation.md`, `lib/dala/bluetooth.ex`, `lib/dala/wifi.ex` |
| Bluetooth/WiFi setup scripts | `scripts/ios_setup.sh`, `scripts/android_setup.sh` |
| iOS Bluetooth native code | `ios/DalaBluetoothManager.{h,m}`, `ios/DalaBluetoothCInterface.m` |
| Android Bluetooth/WiFi bridge | `android/src/main/java/com/example/dala/DalaBridge.java` |
| Generator templates (dala_new) | `dala_new/priv/templates/dala.new/` |
| Build / release tooling | `dala_dev/scripts/release/`, `dala_dev/build_release.md` |

## iOS ML Support (Nx ecosystem)

Dala supports machine learning on iOS via the Nx ecosystem:

- **Nx**: Pure Elixir, works on any platform ✅
- **Axon**: Neural networks, pure Elixir ✅
- **EMLX**: MLX backend for Apple Silicon — **recommended for iOS** ⚠️

**Not supported on iOS:** Emily (macOS-only), NxIREE, EXLA/XLA, Torchx.

Key constraints:
1. **No JIT on iOS devices** — W^X policy blocks JIT. Set `LIBMLX_ENABLE_JIT=false`.
2. **Metal GPU available** — EMLX uses MLX with Metal on iOS devices and simulator.
3. **Unified memory** — Apple Silicon's shared CPU/GPU memory makes EMLX efficient.

Helper modules: `Dala.ML.EMLX`, `Dala.ML.Nx` in `lib/dala/ml/`.
Full guide: `guides/ios_ml_support.md`

## 20. **Bluetooth and WiFi support.**
    Dala provides full BLE and WiFi APIs via `Dala.Bluetooth` and `Dala.WiFi` modules.
    
    **One-command setup:**
    ```bash
    mix dala.setup_bluetooth_wifi              # set up both platforms
    mix dala.setup_bluetooth_wifi --platform ios   # iOS only
    mix dala.setup_bluetooth_wifi --check          # verify without changes
    mix dala.bt_setup                              # shorter alias
    ```
    
    **Runtime API:**
    ```elixir
    Dala.Bluetooth.state()                        # :powered_on | :powered_off | ...
    Dala.Bluetooth.start_scan(socket)              # scan for BLE devices
    Dala.Bluetooth.connect(socket, device_id)      # connect to device
    Dala.Bluetooth.read_characteristic(socket, ...)  # GATT read
    Dala.WiFi.current_network()                   # %{connected: true, ssid: ...}
    Dala.WiFi.connected?()                        # true | false
    Dala.Setup.diagnostic()                       # full BT+WiFi diagnostic
    Dala.Setup.print_diagnostic()                 # print report to console
    ```
    
    **Events arrive as handle_info:**
    ```elixir
    handle_info({:bluetooth, :device_found, %{id: id, name: name, rssi: rssi}}, socket)
    handle_info({:bluetooth, :device_connected, %{id: id}}, socket)
    handle_info({:wifi, :state_changed, %{connected: bool, ssid: ssid}}, socket)
    ```
    
    **iOS:** CoreBluetooth via `DalaBluetoothManager` (ObjC) → C interface → Rust NIF.
    **Android:** `DalaBridge.java` → JNI → Rust NIF.
    
    **Permissions:** Request via `Dala.Permissions.request(socket, :bluetooth)` / `:wifi`.
    
    **Setup modules:** `Dala.Setup.IOS`, `Dala.Setup.Android` for programmatic setup.
    **Setup scripts:** `scripts/ios_setup.sh`, `scripts/android_setup.sh`.
    **Full docs:** `docs/bluetooth_wifi_implementation.md`.

## Conventions worth knowing

- **Terse responses.** Default to short, dense communication. The user reads code
  changes via diff; don't recap them in chat.
- **No premature abstractions.** Three similar lines beats a half-baked helper.
- **No comments explaining the code.** Comments explain *why* — invariants,
  hidden constraints, surprising behavior. Never the *what*.
- **Trust internal callers.** Don't add validation/error handling for cases
  that can't happen. Validate at system boundaries (user input, external APIs).
- **Don't add features beyond what was requested.** A bug fix doesn't need
  surrounding cleanup; a one-shot doesn't need a helper.

## Hex package contents

The `package` function in `mix.exs` defines what goes into the Hex tarball.
Currently: `lib/ native/ priv/ android/ ios/ assets/ mix.exs mix.lock README.md LICENSE`.

### What's included

| Directory | Purpose |
|-----------|--------|
| `lib/` | Elixir source code |
| `native/dala_nif/` | Rust NIF source (built by Rustler during `mix compile`) |
| `native/dala_beam/` | Rust BEAM integration source (EPMD, driver tabs) |
| `android/jni/` | Android NDK C bridge + Rust source for BEAM |
| `ios/` | iOS native files (.m, .h, .swift) + Rust source for BEAM |
| `priv/tags/` | Platform tags for `Dala.Native` |
| `assets/` | Logo and visual assets |

### What's explicitly excluded (via `.gitignore` + disk cleanup)

| Pattern | Why |
|---------|----|
| `**/target/` | Rust build artifacts (58MB+ in `android/jni/rust/target/`) |
| `priv/native/*.so`, `*.dylib` | Pre-compiled NIFs — built during `mix compile` |

### Key gotcha

`mix hex.build` packages **files on disk**, not just git-tracked files.
Even `git rm --cached` won't help if the files still exist on disk —
they'll be included in the tarball. Always delete build artifacts from
 disk before building:

```bash
rm -rf android/jni/rust/target/ ios/rust/target/
rm -f priv/native/*.so
```

The `.gitignore` patterns prevent accidental re-commit, but the immediate
build is about what's on disk.

### Package size check

```bash
mix hex.build 2>&1 | tail -5  # should be under 16MB compressed
ls -lh dala-*.tar              # typical size: ~385KB
```

---

## Keep this file up to date

The next agent's first decision will be informed by this file. Stale guidance
here causes wrong decisions everywhere downstream.

When you change something this doc describes — repo topology, conventions,
gotchas, a new piece of CLI surface area, a deprecated workflow — **update
this file in the same commit**. Not in a follow-up. The history of "I'll fix
the docs later" is that it doesn't happen.

If you discover a gotcha that bit you — something that should have been on the
pre-empt list but wasn't — add it to rule #N+1 with a one-line summary and a
link to the commit/test that demonstrates it. Future you will thank present
you.
