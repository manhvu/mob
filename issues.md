# Issues

Tracked items not yet addressed. Each section captures the symptom, why it
happens, and what a fix would look like — so the next session can pick one
up without re-deriving context.

## 1. Disable `phoenix_live_reload` on iOS device builds

**Symptom** — `beam_stdout.log` on launch:
```
[error] `priv` dir for `:file_system` application is not available in current runtime,
        appoint executable file with `config.exs` or `FILESYSTEM_FSMAC_EXECUTABLE_FILE` env.
[error] Can't find executable `mac_listener`
[warning] Not able to start file_system worker, reason: {:error, :fs_mac_bootstrap_error}
[warning] Could not start Phoenix live-reload because we cannot listen to the file system.
```

**Why** — LiveReload spawns the macOS `mac_listener` binary to watch the project tree
for file changes. It can't possibly work on iOS device (no shell, no fork, no host
filesystem to watch), and the file isn't bundled. Phoenix falls back gracefully
("You don't need to worry!") but the noise pollutes the log.

**Fix** — in the on-device `Application.put_env` for the Endpoint (lives in
`live_view_patcher.ex` → `mob_live_app_content/4`), explicitly disable reload:

```elixir
Application.put_env(:#{app_name}, #{module_name}Web.Endpoint,
  # ... existing config ...
  code_reloader: false,
  watchers: [],
  live_reload: false  # ← add this
)
```

Or remove `:phoenix_live_reload` from the `extra_applications` list entirely
when running on-device (it's a dev-only dep anyway).

---

## 2. Silence `:esbuild` / `:tailwind` startup warnings on-device

**Symptom** — same log:
```
[warning] esbuild version is not configured. Please set it in your config files:
    config :esbuild, :version, "0.25.0"
[warning] tailwind version is not configured. Please set it in your config files:
    config :tailwind, :version, "3.4.6"
```

**Why** — both `:esbuild` and `:tailwind` are dev-time asset-compilation tools.
They're listed as runtime applications in the host project, so they get started
on-device too via `Application.ensure_all_started`. They warn about missing
version configs because the dev-only `config/dev.exs` doesn't get bundled.

**Fix options** (cheapest first):

- **(a) Set the versions** in `mob_app.ex` before `ensure_all_started`:
  ```elixir
  Application.put_env(:esbuild, :version, "0.25.0")
  Application.put_env(:tailwind, :version, "3.4.6")
  ```
  Cosmetic — the tools never actually run on-device, but the warnings go away.

- **(b) Mark them runtime-only false** in the generated `mix.exs`:
  ```elixir
  {:esbuild, "~> 0.8", runtime: false},
  {:tailwind, "~> 0.2", runtime: false},
  ```
  Cleaner — they're build-time-only deps, no reason to start them at runtime.
  Existing `mix.exs` template emits `runtime: Mix.env() == :dev` which is correct
  for host builds; verify the generator is doing this for LV-mode projects.

---

## 3. WebSocket → longpoll fallback in WKWebView

**Symptom** — the LiveView client connects three times within ~70ms during
mount, with the second and third using longpoll:

```
13:20:00.097 [info] CONNECTED TO Phoenix.LiveView.Socket in 2ms
  Transport: :websocket
13:20:00.155 [info] CONNECTED TO Phoenix.LiveView.Socket in 29µs
  Transport: :longpoll
13:20:00.164 [info] CONNECTED TO Phoenix.LiveView.Socket in 18µs
  Transport: :longpoll
[debug] Duplicate channel join for topic "lv:phx-..."
        Closing existing channel for new join.
```

Phoenix handles the duplicate join gracefully, but the WebSocket-then-longpoll
churn is unexpected on a loopback connection that should just work.

**Hypotheses to check**

1. **WKWebView WebSocket on loopback** — does WKWebView allow plain `ws://` to
   `127.0.0.1` without ATS exception? `Info.plist` may need `NSAllowsLocalNetworking`
   or per-domain `NSExceptionAllowsInsecureHTTPLoads`. Test: open the page in
   mobile Safari instead of WKWebView and see whether the longpoll fallback
   still happens.

2. **`check_origin` rejecting the WKWebView origin** — Phoenix is at
   `127.0.0.1:4200` but the WKWebView load might present a different `Origin`
   header depending on how the URL was loaded. If `check_origin` rejects the
   first WS, the client retries on longpoll. The current on-device config has
   `check_origin: false`, but the LiveView socket may still apply per-socket
   origin checks. Worth grep'ing the generated endpoint config for any
   `check_origin` overrides.

3. **Bandit websocket upgrade behaviour** — Bandit 1.x may send the
   `Sec-WebSocket-Accept` response after a delay long enough that the client's
   open-timeout expires and falls back. Check the Bandit version in the
   on-device runtime vs the host dev server.

**Investigation tooling** — WKWebView supports remote inspection via Safari's
Develop menu when the device is plugged in. Settings → Safari → Advanced →
Web Inspector = on. Then Safari → Develop → [iPhone name] → ToyLvApp → choose
the page. The WebSocket frames + console errors there will say definitively
why the connection drops.

**Not urgent** — the longpoll fallback works correctly. Worth fixing because
(a) WS is faster, (b) the duplicate joins burn CPU on every nav, (c) it
suggests something in the loopback WS path is fragile and might bite worse
later (intermittent disconnects under load).
