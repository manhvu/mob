# LiveView on iOS and Android (Mob) — What It Took

This documents the fixes required to get Phoenix LiveView running fully on-device
inside a native WebView. Use this when the setup breaks or when setting up a new app.

The working reference is `/tmp/lv_test` (deployed to iOS simulator and Android emulator/Moto phone in April 2026).
`mix mob.enable liveview` automates the parts that apply to every new project.

---

## Architecture

### iOS
```
iOS native (ObjC/Swift)
  └─ mob_beam.m  →  lv_test:start()  →  LvTest.MobApp.start/0
       └─ Application.put_env → ensure_all_started(:lv_test)
            └─ Phoenix/Bandit on 127.0.0.1:4200
                 └─ WKWebView loads http://127.0.0.1:4200/
                      └─ LiveView WebSocket ws://127.0.0.1:4200/live
```

The iOS simulator shares the host loopback, so 127.0.0.1 works from both sides.
Port 4200 avoids conflict with `mix phx.server` running on the host at 4000.

### Android
```
Android native (Kotlin/Compose)
  └─ mob_beam.c  →  lv_test:start()  →  LvTest.MobApp.start/0
       └─ Application.put_env → ensure_all_started(:lv_test)
            └─ Phoenix/Bandit on 127.0.0.1:4200
                 └─ Android WebView loads http://127.0.0.1:4200/
                      └─ LiveView WebSocket ws://127.0.0.1:4200/live
```

The Android emulator and real device both have their own loopback interface, so
127.0.0.1 resolves to the device itself — same as iOS. No port forwarding needed.

---

---

## Fixes that apply to both iOS and Android

---

## Fix 1: Mix config is never loaded on-device

`config/dev.exs`, `config/runtime.exs`, etc. are never processed when the BEAM
starts from a native binary. You cannot rely on `Application.get_env/3` returning
values set by config files.

**Solution:** Use `Application.put_env/3` in `MobApp.start/0` *before* calling
`Application.ensure_all_started/1`.

```elixir
Application.put_env(:lv_test, LvTestWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4200],
  server: true,
  secret_key_base: "...",
  ...
)
{:ok, _} = Application.ensure_all_started(:lv_test)
```

---

## Fix 2: Must specify Bandit adapter explicitly

Phoenix 1.7 defaults to Cowboy if no adapter is specified, but `lv_test` only has
Bandit in its deps. Without the explicit adapter key, Phoenix refuses to start.

```elixir
Application.put_env(:lv_test, LvTestWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  ...
)
```

---

## Fix 3: Mob.ComponentRegistry must be started manually

In a normal Mob app, `Mob.App` starts `Mob.ComponentRegistry` as part of its
supervision tree. In LiveView mode we skip `Mob.App` entirely. If you call
`Mob.Screen.start_root/1` without `ComponentRegistry` running, it crashes.

Start it explicitly after `ensure_all_started/1`:

```elixir
{:ok, _} = Application.ensure_all_started(:lv_test)
{:ok, _} = Mob.ComponentRegistry.start_link()
Mob.Screen.start_root(LvTest.MobScreen)
```

---

## Fix 4: Route to a LiveView, not PageController

`mix phx.new` generates a `PageController` route. On-device there is no template
compilation environment, so rendering Phoenix HTML templates via the controller
stack fails. Use a LiveView instead:

In `router.ex`:
```elixir
# Before
get "/", PageController, :home

# After
live "/", PageLive
```

Create `lib/lv_test_web/live/page_live.ex`:
```elixir
defmodule LvTestWeb.PageLive do
  use LvTestWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :pong, false)}
  end

  def render(assigns) do
    ~H"""
    <button phx-click="ping">Ping</button>
    <%= if @pong do %>Pong!<% end %>
    """
  end

  def handle_event("ping", _params, socket) do
    {:noreply, assign(socket, :pong, true)}
  end
end
```

---

## Fix 5: Phoenix JS/CSS assets must be deployed to BEAMS_DIR/priv/static

In the flat BEAMS_DIR layout used by build.sh, `code:lib_dir(:lv_test)` resolves
to `BEAMS_DIR` itself (not a nested `lib/lv_test` dir). `Plug.Static` derives the
priv path from `code:priv_dir/1`, which becomes `BEAMS_DIR/priv/`.

Build and copy assets in build.sh:

```bash
mix assets.build
mkdir -p "$BEAMS_DIR/priv/static"
cp -r priv/static/. "$BEAMS_DIR/priv/static/"
# Also sync into /tmp/otp-ios-sim (which mob_beam.m hardcodes as OTP_ROOT)
rsync -a "$BEAMS_DIR/priv/" "/tmp/otp-ios-sim/lv_test/priv/"
```

Without this step the WebView loads a blank page — the HTML arrives but LiveView's
JavaScript never executes because `app.js` returns 404.

---

## Fix 6: Crypto shim — OTP builds for mobile have no OpenSSL NIF

**Applies to: iOS and Android**

Neither the iOS nor Android OTP build includes `:crypto` (no OpenSSL). Phoenix's
session system (`plug_crypto`) uses `:crypto.pbkdf2_hmac/5` to derive session keys,
`:crypto.mac/4` for HMAC verification, and `:crypto.exor/2` for CSRF nonce masking.
Without these, every request crashes.

The fix is a pure-Erlang shim compiled with `erlc` on the host and deployed alongside
the app's BEAM files. `mob_dev` generates and deploys it automatically as part of
`mix mob.deploy`. Critical exports:

- `pbkdf2_hmac/5` — session key derivation (PBKDF2 using HMAC-MD5 as PRF)
- `exor/2` — XORs two binaries; used by `Plug.CSRFProtection.mask/1`
- `strong_rand_bytes/1` — delegates to `rand:bytes/1` (OTP 26+)
- `mac/3,4` — HMAC-MD5; used by plug_crypto for cookie/token verification
- `hash/2` — delegates to `erlang:md5/1`

**Security note:** The shim uses MD5 everywhere OpenSSL would use SHA-256. This is
intentional — MD5 is available as an Erlang BIF without any NIF. For a loopback-only
dev server there is no meaningful attack surface. Do not ship this in a production app
with external network access.

See `MobDev.Deployer.generate_crypto_shim/0` for the current implementation.

---

## Fix 7: xor_bytes must zip pairs, not take the cartesian product

**Applies to: iOS and Android**

The obvious Erlang implementation of byte-wise XOR:

```erlang
%% WRONG — cartesian product, produces N² bytes
xor_bytes(A, B) ->
    list_to_binary([X bxor Y || <<X>> <= A, <<Y>> <= B]).
```

This generates N² elements (every combination of each byte of A with every byte of
B), not N (element-wise pairs). In `pbkdf2_iterate`, the accumulator's size grows
exponentially across iterations, causing the process to hang and eventually OOM.

**Correct implementation — recursive zip:**

```erlang
xor_bytes(A, B) -> xor_bytes(A, B, []).
xor_bytes(<<X, Ra/binary>>, <<Y, Rb/binary>>, Acc) ->
    xor_bytes(Ra, Rb, [X bxor Y | Acc]);
xor_bytes(<<>>, <<>>, Acc) ->
    list_to_binary(lists:reverse(Acc)).
```

---

## Fix 8: Normalize iodata inputs in crypto shim

**Applies to: iOS and Android**

`plug_crypto` passes iodata (lists of binaries, nested lists, etc.), not flat
binaries, to crypto functions. `erlang:md5/1` accepts iodata but binary pattern
matching does not.

Normalize all inputs at every entry point:

```erlang
pbkdf2_hmac(_DigestType, Password, Salt, Iterations, DerivedKeyLen) ->
    Pwd = iolist_to_binary(Password),
    S   = iolist_to_binary(Salt),
    ...

mac(hmac, _HashAlg, Key, Data) ->
    hmac_md5(iolist_to_binary(Key), iolist_to_binary(Data));

exor(A, B) ->
    xor_bytes(iolist_to_binary(A), iolist_to_binary(B)).
```

---

## Fix 9: SSL — thousand_island requires :ssl but mobile OTP builds omit it

**Applies to: iOS and Android**

`thousand_island` lists `:ssl` as a required OTP application. iOS OTP doesn't
include ssl. But ssl is implemented entirely in Erlang (no NIFs), so host macOS
`.beam` files run identically on the iOS simulator.

Copy ssl from the host OTP in build.sh:

```bash
HOST_SSL_DIR=$(ls -d ~/.local/share/mise/installs/erlang/*/lib/ssl-* 2>/dev/null \
    | sort -V | tail -1)
if [ -n "$HOST_SSL_DIR" ]; then
    cp "$HOST_SSL_DIR/ebin/"*.beam "$BEAMS_DIR/"
    cp "$HOST_SSL_DIR/ebin/ssl.app" "$BEAMS_DIR/"
fi
```

Note: No TLS sockets are actually opened (loopback HTTP only), but ssl must start
successfully for thousand_island to boot.

---

## Fix 10: Use glob loop to copy all compiled deps

**Applies to: iOS** (Android uses `mix mob.deploy` which already collects all dep ebins)

Hardcoding individual dep names in build.sh is brittle. When deps change, the list
goes stale and modules are missing on-device.

```bash
# Before (brittle)
cp _build/dev/lib/phoenix/ebin/* "$BEAMS_DIR/"
cp _build/dev/lib/plug/ebin/* "$BEAMS_DIR/"
# ... etc

# After (glob loop — copies everything)
for lib_dir in _build/dev/lib/*/ebin; do
    cp "$lib_dir"/* "$BEAMS_DIR/" 2>/dev/null || true
done
```

The `2>/dev/null || true` suppresses errors for deps that have no .beam files
(e.g., deps with only header files or native code).

---

## Android-only fixes

These issues do not exist on iOS. They were discovered during the first Android
LiveView deployment in April 2026.

---

## Fix A1: `"web_view"` type name mismatch in MobBridge.kt

**Symptom:** App shows a solid white screen. The BEAM starts, Phoenix is listening on
port 4200 (`ss -tlnp` confirms it), and step 5 logs `ok` — but nothing is ever rendered.

**Root cause:** `Mob.UI.webview/1` in `mob/lib/mob/ui.ex` returns `%{type: :web_view, ...}`.
`Mob.Renderer` converts that atom to a string via `Atom.to_string(:web_view)`, producing
`"web_view"` in the JSON payload sent to the native layer. But `RenderNode` in
`MobBridge.kt` had:

```kotlin
"webview" -> MobWebView(node, m)   // wrong — underscore missing
```

The switch case never matched, so Compose never created a `MobWebView`, and the
`_rootState.node` remained null — blank screen.

**Fix:** Change the case string to match the snake_case atom:

```kotlin
"web_view" -> MobWebView(node, m)
```

**Where:** `android/app/src/main/java/com/mob/<app>/MobBridge.kt` — the `RenderNode`
`when` block. Fixed in `lv_test` and `mob_demo` in April 2026. Any project created before
that fix must be patched manually.

**How to spot it:** `_rootState.node` is non-null (Compose received JSON) but the screen
is white. Add a log at the `else ->` branch of `RenderNode` to see what type string is
arriving. If you see `"web_view"` logged and no WebView renders, this is the bug.

---

## Fix A2: Android blocks cleartext HTTP to 127.0.0.1 by default

**Symptom:** The WebView loads but shows the Android "Webpage not available" error page
with error code `net::ERR_CLEARTEXT_NOT_PERMITTED`.

**Root cause:** Android 9+ enforces a system-wide policy that blocks plaintext HTTP
traffic by default. This applies even to loopback (127.0.0.1). Since the Phoenix
endpoint runs over plain HTTP (no TLS on loopback), the WebView refuses to load it.

**Fix:** Add a network security config that explicitly permits cleartext to 127.0.0.1
and localhost.

`android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```

`android/app/src/main/AndroidManifest.xml` — add the attribute to `<application>`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

**Automated:** `mix mob.enable liveview` now does both of these steps automatically
(idempotent). See `MobDev.Enable.inject_android_network_security_config/1` and
`MobDev.Enable.network_security_config_xml/0`.

---

## Fix A3: Compose accessibility tree is invisible to inspection tools

**Not a bug — just a debugging pitfall.**

When debugging a blank Android screen, `adb shell uiautomator dump` and similar tools
(including the `inspect_ui` MCP tool) return an empty view hierarchy. This is not
evidence that nothing is rendered — Compose bypasses the traditional Android
accessibility hierarchy by default.

To see what Compose is actually rendering, read logcat and check `_rootState`:

```bash
adb -s <device> shell logcat | grep -E "Elixir|MobBridge|step [0-9]"
```

Alternatively, add a `Log.d("MobBridge", "RenderNode type=${node.type}")` call inside
`RenderNode` in `MobBridge.kt` to confirm what type string the BEAM sent. This is much
faster than trying to interpret screenshot pixels.

---

## Fix A4: Elixir stdlib version mismatch after host Elixir upgrade

**Applies to: Android**

**Symptom:** `function_clause` crash in `Elixir.Regex.safe_run` when Phoenix starts on the device:

```
{function_clause,
  [{'Elixir.Regex',safe_run,
    [#{re_pattern => {re_pattern,0,0,0,#Ref<...>}, ...},
     <<"localhost">>,
     [{capture,none}]],
    [{file,"lib/regex.ex"},{line,524}]},
   {'Elixir.Phoenix.Endpoint.Supervisor',build_url,2, ...}
```

**Root cause:** The mob Android OTP bundles a specific Elixir stdlib version. The Elixir stdlib (including `Regex`) is pushed to the device by `mix mob.deploy --native` using the host Elixir at that time. If the host Elixir is later upgraded (e.g. 1.18.4 → 1.19.5), the device retains the old stdlib. Phoenix compiled with Elixir 1.19.5 embeds regex patterns in OTP 28's NIF format; Elixir 1.18.4's `Regex.safe_run` doesn't handle that format → `function_clause`.

**Fix:** `mix mob.deploy` now automatically detects Elixir version mismatches between host and device and re-pushes the stdlib (elixir, logger, eex) when they differ. This happens transparently on every deploy with no extra flags.

**Manual workaround** (before the fix was in `mob_dev`):

```bash
ELIXIR_EBIN=$(elixir -e "IO.puts(:code.lib_dir(:elixir))")/ebin
adb -s SERIAL shell "run-as PKG mkdir -p files/otp/lib/elixir/ebin"
adb -s SERIAL push "$ELIXIR_EBIN/." /data/data/PKG/files/otp/lib/elixir/ebin/
am force-stop PKG && am start -n PKG/.MainActivity
```

**Where:** `mob_dev/lib/mob_dev/deployer.ex` — `sync_elixir_stdlib_android/1`.

---

## Summary table

### Shared (iOS + Android)

| # | Fix | Symptom without it |
|---|-----|--------------------|
| 1 | `put_env` before `ensure_all_started` | Endpoint never starts (wrong config) |
| 2 | `adapter: Bandit.PhoenixAdapter` | Phoenix refuses to start |
| 3 | `Mob.ComponentRegistry.start_link()` | Crash calling `start_root` |
| 4 | Route to `PageLive`, not `PageController` | HTTP 500 on every request |
| 5 | Deploy `priv/static` to BEAMS_DIR | Blank WebView (JS 404) |
| 6 | Full crypto shim (`pbkdf2_hmac`, `exor`, `mac`, `hash`) | Crash on every request |
| 7 | Zip pairs in `xor_bytes`, not cartesian product | Process hang / OOM in pbkdf2 |
| 8 | `iolist_to_binary` on all crypto shim inputs | `ArgumentError` in binary construction |
| 9 | SSL BEAM files from host OTP | `thousand_island` fails to start |
| 10 | Glob loop for dep BEAM copy (iOS) / `mob.deploy` (Android) | Missing module errors at runtime |

### Android-only

| # | Fix | Symptom without it |
|---|-----|--------------------|
| A1 | `"web_view"` (not `"webview"`) in `MobBridge.kt` `RenderNode` | Solid white screen, no error |
| A2 | `network_security_config.xml` + manifest attribute | `net::ERR_CLEARTEXT_NOT_PERMITTED` |
| A3 | (awareness) Compose hides from `uiautomator` / `inspect_ui` | Misleading "empty" UI dump |
| A4 | Elixir stdlib version must match host (auto-synced by `mob.deploy`) | `function_clause` in `Regex.safe_run` on endpoint start |

---

## Relevant files

- `/tmp/lv_test/` — working reference project (iOS + Android, April 2026)
- `/tmp/lv_test/lib/lv_test/mob_app.ex` — the on-device BEAM entry point (shared)
- `/tmp/lv_test/ios/build.sh` — iOS build script with all shared fixes applied
- `/tmp/lv_test/android/app/src/main/java/com/mob/lv_test/MobBridge.kt` — Android Compose renderer (fix A1 here)
- `/tmp/lv_test/android/app/src/main/res/xml/network_security_config.xml` — cleartext whitelist (fix A2)
- `mob_dev/lib/mob_dev/deployer.ex` — `generate_crypto_shim/0` (fix 6, shared)
- `mob_dev/lib/mob_dev/enable.ex` — `inject_android_network_security_config/1` (fix A2, automated)
- `mob/lib/mob/ui.ex` — `Mob.UI.webview/1` generates `:web_view` atom (the type A1 must match)
