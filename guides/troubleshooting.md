# Troubleshooting

Common issues encountered during development and how to resolve them.

## EPMD port conflict with adb (port 4369)

**Symptom:** App crashes on launch, Erlang distribution fails to start, or
`mix mob.connect` hangs indefinitely. Often surfaces as a silent failure with
no obvious error message — the node never comes online.

**Cause:** EPMD (Erlang Port Mapper Daemon) is registered with IANA on port
4369. The Android Debug Bridge also uses port 4369 in certain configurations.
When both are active on the same machine, EPMD fails to bind and Erlang
distribution cannot start — which means the device BEAM can't register itself
and `mix mob.connect` can never find it.

**Fix:** Move EPMD to a port nothing else uses. Port 4380 is a safe choice.
Set `ERL_EPMD_PORT` in both the device BEAM startup and your local dev
environment.

In `mob.exs`:

```elixir
config :mob_dev, epmd_port: 4380
```

In your app's `application.ex`, pass the port when starting distribution:

```elixir
Mob.Dist.ensure_started(
  node:      :"my_app_android@127.0.0.1",
  cookie:    :mob_secret,
  epmd_port: Application.get_env(:mob_dev, :epmd_port, 4369)
)
```

`mob_dev` will update the `adb reverse` tunnel to use the configured port
automatically.

**Why 4369 conflicts:** EPMD's port 4369 dates from 1993 (predating Android by
15 years). The collision is coincidental and there is no Erlang inside the
Android toolchain. Moving off the default port also has a secondary benefit:
Mob's device nodes become isolated from any other Elixir processes running on
your Mac.

---

## Distribution in production

In development, `Mob.Dist.ensure_started/1` runs so `mix mob.connect` can
reach the app. In production the picture is different but not simply "turn it
off" — it depends on whether you want OTA BEAM updates.

**No OTA updates:** gate distribution on environment and leave it off in prod.
`Mob.Dist.ensure_started/1` is a no-op unless explicitly called, so production
builds are safe by default:

```elixir
# lib/my_app/application.ex
if Application.get_env(:my_app, :env) == :dev do
  Mob.Dist.ensure_started(node: :"my_app_ios@127.0.0.1", cookie: :mob_secret)
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

## `mix mob.connect` finds no nodes

**Check in order:**

1. **Is the app running on the device?**
   ```bash
   mix mob.devices   # confirms device is visible to adb / xcrun
   ```

2. **Did distribution start on the device?**
   Check the device log for `[mob] distribution started` — if absent, the
   `Mob.Dist.ensure_started/1` call either wasn't reached or failed silently
   (often due to the EPMD port conflict above).

3. **Do cookies match?**
   The cookie in your app's `Mob.Dist.ensure_started/1` call must match the
   `--cookie` flag passed to `mix mob.connect` (default: `mob_secret`).

4. **iOS: is the simulator booted?**
   ```bash
   xcrun simctl list devices | grep Booted
   ```

5. **Android: are the adb tunnels up?**
   ```bash
   adb reverse --list   # should show tcp:4369 tcp:4369 (or your custom port)
   adb forward --list   # should show tcp:9100 tcp:9100
   ```
   If missing, re-run `mix mob.connect` — it sets these up automatically on
   each run.

---

## Hot-push succeeds but changes don't appear

`nl(MyApp.SomeScreen)` returns `{:ok, [...]}` but the running screen still
shows old behaviour.

**Cause:** The screen process is still executing the old version of the module.
Hot code loading in the BEAM takes effect on the *next function call* — if the
screen is in the middle of a `handle_event/3` or `handle_info/2` call, it
finishes with the old code first.

**Fix:** Trigger any event on the screen (a tap, a `Mob.Test.tap/2`) to force
the process to make a new function call, picking up the new code. For layout
changes, navigate away and back so `render/1` is called fresh.

If you need a guaranteed clean reload, use `mix mob.deploy` (restarts the app)
rather than hot-push.

---

## Android: app crashes on first distribution startup

**Symptom:** App starts successfully, then crashes 3–5 seconds later. Logcat
shows a signal abort or mutex error.

**Cause:** On Android, starting Erlang distribution too early (before the hwui
thread pool is fully initialised) causes a `pthread_mutex_lock on destroyed
mutex` SIGABRT. This is why `Mob.Dist.ensure_started/1` defers `Node.start/2`
by 3 seconds on Android.

**Fix:** Make sure you are calling `Mob.Dist.ensure_started/1` and not calling
`Node.start/2` directly. If you need distribution earlier, increase the defer
delay:

```elixir
Mob.Dist.ensure_started(node: :"my_app_android@127.0.0.1", cookie: :mob_secret, delay: 5000)
```

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
`Mob.Dist.ensure_started/1` and update `mob.exs` accordingly.
