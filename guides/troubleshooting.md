# Troubleshooting

## Start here: mix dala.doctor

Before diving into specific issues, run:

```bash
mix dala.doctor
```

This checks your entire environment in one go — required tools, `dala.exs`
configuration, OTP runtime caches, and connected devices — and prints specific
fix instructions for anything wrong. Most setup problems are caught here.

```
=== Dala Doctor ===

Tools
  ✓ adb — /usr/bin/adb
  ✗ xcrun — not found
      Install Xcode command-line tools:
      xcode-select --install

Project
  ✗ dala_dir — path not found: /Users/you/old/path/to/dala
      Update dala.exs — the path must exist on this machine

OTP Cache
  ✗ OTP iOS simulator — directory exists but contains no erts-* — extraction was incomplete
      Remove the stale directory and re-download:
      rm -rf ~/.dala/cache/otp-ios-sim-73ba6e0f
      mix dala.install

Devices
  ⚠ Android devices — none connected
      Connect a device via USB (enable USB debugging) or start an emulator

3 failures — fix the issues above and re-run mix dala.doctor.
```

The sections below cover issues that `mix dala.doctor` doesn't catch — runtime
behaviour, distribution quirks, and platform-specific edge cases.

---

Common issues encountered during development and how to resolve them.

## Screen never renders — `Dala.Screen.start_root` silent failure

**Symptom:** App sits on "Starting BEAM…" splash forever. No crash, no progress.

**Cause:** `Dala.Screen.start_root/1` returns `{:error, reason}` or crashes inside `init/1`.
If you don't pattern-match the return value, the screen never renders and the failure is silent.
(Agents.md rule 2)

**Fix:** Always pattern-match in `on_start/0`:

```elixir
# lib/my_app/application.ex
{:ok, _pid} = Dala.Screen.start_root(MyApp.HomeScreen)
```

If it crashes, the `= ` forces a loud failure. Check device logs:

```bash
adb logcat | grep Elixir   # Android
# iOS: Console.app → select device → filter "dala"
```

---

## Early startup debugging — no Logger output

**Symptom:** You added `Logger.info/1` in `on_start/0` or `init/1` but see nothing.

**Cause:** `Logger` isn't rerouted to NSLog/logcat until `Dala.App.start` runs.
Before that point, `Logger` output goes to stderr and is invisible on device.
(Agents.md rule 10)

**Fix:** Use `:dala_nif.log/1` for early startup diagnostics:

```elixir
:dala_nif.log("Reached on_start")
# ... your init code ...
:dala_nif.log("About to start root screen")
```

Switch to `Logger` once the screen is running and you see "Dala.App started" in the log.

---

## `Path.expand` crashes on Android — default args evaluate eagerly

**Symptom:** App crashes on Android with `System.user_home!/1` error.

**Cause:** Code like `System.get_env("ROOTDIR", Path.expand("~/..."))` evaluates
`Path.expand` *every call*, regardless of whether `ROOTDIR` is set. On Android,
`HOME` env var isn't set, so `Path.expand` calls `System.user_home!()` which raises.
(Agents.md rule 1)

**Fix:** Use `case` or `||` to defer expansion:

```elixir
# Wrong
defp root_dir do
  System.get_env("ROOTDIR", Path.expand("~/my_app"))
end

# Right
defp root_dir do
  case System.get_env("ROOTDIR") do
    nil -> Path.expand("~/my_app")
    dir -> dir
  end
end
```

---

## Elixir or Hex version too old

**Symptom:** `mix deps.get` or `mix dala.install` fails with errors like
`no matching version found`, `invalid requirement`, or dependency resolution
failures that look unrelated to your code.

**Cause:** Dala requires Elixir 1.18 or later. Older versions of Hex (pre-2.0)
also have issues resolving some package requirements used by `dala_dev`.

**Check:**

```bash
mix dala.doctor   # shows Elixir, OTP, and Hex versions with ✓/✗
elixir --version
mix hex --version
```

**Fix — Hex** (fast, no version manager needed):

```bash
mix local.hex --force
```

**Fix — Elixir** (choose the method that matches how you installed it):

```bash
# mise
mise install elixir@latest && mise use elixir@latest

# asdf
asdf install elixir latest && asdf global elixir latest

# Homebrew
brew upgrade elixir

# Nix / nix-shell: update your shell.nix or flake.nix to use elixir_1_18

# Official installer: https://elixir-lang.org/install.html
```

After upgrading, re-fetch deps:

```bash
mix deps.get
mix dala.doctor   # confirm versions are green
```

---

## OTP cache: "No erts-* directory found"

**Symptom:** `mix dala.deploy --native` fails with:

```
ERROR: No erts-* directory found in ~/.dala/cache/otp-ios-sim-73ba6e0f
       Have you built OTP for iOS simulator?
```

**Cause:** The OTP cache directory was created during a previous download attempt
that failed partway through (network error, SSL failure, or curl exiting non-zero).
Because the directory exists, subsequent runs skip re-downloading, so the problem
persists across restarts.

This is particularly common on **Nix-managed macOS** setups, where Nix provides
its own `curl` binary that uses a different CA certificate store than macOS system
curl. The GitHub release download may fail with an SSL certificate error that isn't
surfaced clearly.

**Fix:**

```bash
mix dala.doctor   # confirms the problem and shows the exact path

rm -rf ~/.dala/cache/otp-ios-sim-73ba6e0f   # remove stale cache
mix dala.install                             # re-download
```

If the download fails again (Nix curl SSL), download the tarball manually using
the system curl:

```bash
/usr/bin/curl -L https://github.com/GenericJam/dala/releases/download/otp-73ba6e0f/otp-ios-sim-73ba6e0f.tar.gz \
  -o /tmp/otp-ios-sim.tar.gz

mkdir -p ~/.dala/cache/otp-ios-sim-73ba6e0f
tar xzf /tmp/otp-ios-sim.tar.gz -C ~/.dala/cache/otp-ios-sim-73ba6e0f --strip-components=1
```

Verify it worked:

```bash
ls ~/.dala/cache/otp-ios-sim-73ba6e0f/erts-*   # should list erts-16.x
mix dala.doctor                                  # should show ✓ for iOS simulator OTP
```

---

## EPMD port conflict with adb (port 4369)

**Symptom:** App crashes on launch, Erlang distribution fails to start, or
`mix dala.connect` hangs indefinitely. Often surfaces as a silent failure with
no obvious error message — the node never comes online.

**Cause:** EPMD (Erlang Port Mapper Daemon) is registered with IANA on port
4369. The Android Debug Bridge also uses port 4369 in certain configurations.
When both are active on the same machine, EPMD fails to bind and Erlang
distribution cannot start — which means the device BEAM can't register itself
and `mix dala.connect` can never find it.

**Fix:** Move EPMD to a port nothing else uses. Port 4380 is a safe choice.
Set `ERL_EPMD_PORT` in both the device BEAM startup and your local dev
environment.

In `dala.exs`:

```elixir
config :dala_dev, epmd_port: 4380
```

In your app's `application.ex`, pass the port when starting distribution:

```elixir
Dala.Dist.ensure_started(
  node:      :"my_app_android@127.0.0.1",
  cookie:    :dala_secret,
  epmd_port: Application.get_env(:dala_dev, :epmd_port, 4369)
)
```

`dala_dev` will update the `adb reverse` tunnel to use the configured port
automatically.

**Why 4369 conflicts:** EPMD's port 4369 dates from 1993 (predating Android by
15 years). The collision is coincidental and there is no Erlang inside the
Android toolchain. Moving off the default port also has a secondary benefit:
Dala's device nodes become isolated from any other Elixir processes running on
your Mac.

---

## Distribution in production

In development, `Dala.Dist.ensure_started/1` runs so `mix dala.connect` can
reach the app. In production the picture is different but not simply "turn it
off" — it depends on whether you want OTA BEAM updates.

**No OTA updates:** gate distribution on environment and leave it off in prod.
`Dala.Dist.ensure_started/1` is a no-op unless explicitly called, so production
builds are safe by default:

```elixir
# lib/my_app/application.ex
if Application.get_env(:my_app, :env) == :dev do
  Dala.Dist.ensure_started(node: :"my_app_ios@127.0.0.1", cookie: :dala_secret)
end
```

**With OTA BEAM updates:** distribution needs to be live, but only during the
update session. The recommended pattern is on-demand: the app polls your server
over HTTP for an update manifest, starts EPMD + distribution only when an
update is available, connects to your update server's BEAM node to receive new
BEAMs via `:code.load_binary`, then shuts distribution back down. Because the
phone initiates the outbound connection, no inbound ports need to be open and
the cookie can be rotated per session via the manifest.

---

## `mix dala.connect` finds no nodes

**Check in order:**

1. **Is the app running on the device?**
   ```bash
   mix dala.devices   # confirms device is visible to adb / xcrun
   ```

2. **Did distribution start on the device?**
   Check the device log for `[dala] distribution started` — if absent, the
   `Dala.Dist.ensure_started/1` call either wasn't reached or failed silently
   (often due to the EPMD port conflict above).

3. **Do cookies match?**
   The cookie in your app's `Dala.Dist.ensure_started/1` call must match the
   `--cookie` flag passed to `mix dala.connect` (default: `dala_secret`).

4. **iOS: is the simulator booted?**
   ```bash
   xcrun simctl list devices | grep Booted
   ```

5. **Android: are the adb tunnels up?**
   ```bash
   adb reverse --list   # should show tcp:4369 tcp:4369 (or your custom port)
   adb forward --list   # should show tcp:9100 tcp:9100
   ```
   If missing, re-run `mix dala.connect` — it sets these up automatically on
   each run.

---

## Hot-push succeeds but changes don't appear

`nl(MyApp.SomeScreen)` returns `{:ok, [...]}` but the running screen still
shows old behaviour.

**Cause:** The screen process is still executing the old version of the module.
Hot code loading in the BEAM takes effect on the *next function call* — if the
screen is in the middle of a `handle_event/3` or `handle_info/2` call, it
finishes with the old code first.

**Fix:** Trigger any event on the screen (a tap, a `Dala.Test.tap/2`) to force
the process to make a new function call, picking up the new code. For layout
changes, navigate away and back so `render/1` is called fresh.

If you need a guaranteed clean reload, use `mix dala.deploy` (restarts the app)
rather than hot-push.

---

## Android: app crashes on first distribution startup

**Symptom:** App starts successfully, then crashes 3–5 seconds later. Logcat
shows a signal abort or mutex error.

**Cause:** On Android, starting Erlang distribution too early (before the hwui
thread pool is fully initialised) causes a `pthread_mutex_lock on destroyed
mutex` SIGABRT. This is why `Dala.Dist.ensure_started/1` defers `Node.start/2`
by 3 seconds on Android.

**Fix:** Make sure you are calling `Dala.Dist.ensure_started/1` and not calling
`Node.start/2` directly. If you need distribution earlier, increase the defer
delay:

```elixir
Dala.Dist.ensure_started(node: :"my_app_android@127.0.0.1", cookie: :dala_secret, delay: 5000)
```

---

## iOS: `Dala.Test.pop` / `pop_to_root` crashes the BEAM

**Symptom:** Calling `Dala.Test.pop(node)`, `Dala.Test.pop_to(node, ...)`, or
`Dala.Test.pop_to_root(node)` causes the iOS BEAM node to crash immediately.
Logcat shows a signal or the node goes offline.

**Cause:** The pop NIF calls SwiftUI's navigation stack from an Erlang distribution
thread. SwiftUI requires all UI mutations to happen on the main thread. The push
path is guarded correctly; the pop path is not yet.

**Workaround:** Drive backward navigation using platform taps instead:

```elixir
# Instead of: Dala.Test.pop_to_root(node)

# iOS — tap the native Back button via MCP:
mcp__ios_simulator__ui_tap(x: 20, y: 60)

# Or navigate forward to the desired screen and reset:
Dala.Test.navigate(node, MyApp.HomeScreen)
```

`Dala.Test.navigate/3` (push) is safe — it does not trigger the crash.

---

## iOS simulator: node connects but RPC calls fail

**Symptom:** `Node.connect/1` returns `true`, `Node.list/0` shows the device
node, but `:rpc.call/4` returns `{:badrpc, :nodedown}` or hangs.

**Cause:** The iOS simulator shares the Mac's network stack, so EPMD
registration works. But if the dist port (default 9101 for iOS) is blocked by
macOS firewall or already in use, the actual distribution channel can't be
established even though EPMD sees the node.

**Fix:** Check if 9101 is in use:

```bash
lsof -i :9101
```

If something else is using it, configure a different dist port in
`Dala.Dist.ensure_started/1` and update `dala.exs` accordingly.
