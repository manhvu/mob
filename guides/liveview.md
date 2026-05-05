# LiveView Mode

LiveView mode lets you ship a dalaile app using only Phoenix LiveView — no native
UI code required. Dala runs a local Phoenix endpoint on the device and wraps it in
a native WebView. LiveView updates travel over the existing WebSocket at loopback
speed (~1–5 ms).

## Setup

Run this from your Dala project root (the directory with `mix.exs`):

```bash
mix dala.enable liveview
```

This does four things:

1. **Generates `lib/<app>/dala_screen.ex`** — a `Dala.Screen` that opens a WebView
   pointing at `http://127.0.0.1:PORT/`
2. **Patches `assets/js/app.js`** — adds the `DalaHook` LiveView hook definition and
   registers it with `LiveSocket`
3. **Patches `root.html.heex`** — adds a hidden `<div id="dala-bridge">` that the hook
   mounts on (see [why this is required](#why-the-hidden-div-is-required))
4. **Creates or updates `dala.exs`** — sets `liveview_port` so `Dala.LiveView.local_url/1`
   knows which port Phoenix is listening on

After running, wire up the screen in your app:

```elixir
# In Dala.App.on_start/0
Dala.Screen.start_root(MyApp.dalaScreen)
```

Make sure Phoenix is running on the port set in `dala.exs` (default: 4000).

---

## The two-bridge architecture

Understanding this is essential when something is not working.

There are **two separate JavaScript bridges** that can route messages between your
page's JS and Elixir. They are mutually exclusive — whichever one is active owns
`window.dala`.

### Bridge 1 — The native bridge

The native WebView (iOS `WKWebView` / Android `WebView`) injects a `window.dala`
object into every page it loads. It routes directly through the NIF, bypassing
LiveView entirely.

```
JS → window.dala.send(data)
   → native postMessage / JavascriptInterface
   → NIF (dala_deliver_webview_message)
   → handle_info({:webview, :message, data}, socket)  ← in your Dala.Screen
```

```
Elixir → Dala.WebView.post_message(socket, data)
       → NIF (webview_post_message)
       → evaluateJavascript("window.dala._dispatch(...)")
       → all window.dala.onMessage handlers in JS
```

### Bridge 2 — The LiveView bridge

When `DalaHook` mounts it **replaces** `window.dala` with a LiveView-backed version.
Messages now travel over the Phoenix WebSocket.

```
JS → window.dala.send(data)
   → LiveView pushEvent("dala_message", data)
   → handle_event("dala_message", data, socket)  ← in your LiveView
```

```
Elixir → push_event(socket, "dala_push", data)
       → LiveView handleEvent("dala_push", handler)
       → all window.dala.onMessage handlers in JS
```

Your JS code does not need to know which bridge is active — the `window.dala` API
is identical in both modes.

---

## Why the hidden div is required

This is the most commonly missed step when setting up LiveView mode manually.

Phoenix LiveView hooks run their `mounted()` callback **only when**:

1. A DOM element with `phx-hook="DalaHook"` exists in the rendered page, **and**
2. The LiveView WebSocket has connected.

Registering `DalaHook` in `app.js` is necessary but not sufficient. Without a
matching DOM element the hook is dormant — it never fires, `window.dala` is never
replaced with the LiveView version, and all JS messages silently use Bridge 1
(the native NIF bridge) instead of Bridge 2 (LiveView).

The symptom: `window.dala.send()` appears to work but `handle_event/3` in your
LiveView never receives anything. The messages arrive in `handle_info/2` in your
`Dala.Screen` instead.

`mix dala.enable liveview` adds this element immediately after `<body>` in
`root.html.heex`:

```html
<div id="dala-bridge" phx-hook="DalaHook" style="display:none"></div>
```

Placing it at the top of `<body>` ensures the hook mounts as early as possible
after LiveView connects, so `window.dala` is overridden before page-specific JS runs.

### Adding it manually

If `mix dala.enable liveview` could not find `root.html.heex`, or you are setting
up manually, add the element anywhere inside `<body>` in whatever layout file
wraps your entire application:

```html
<body>
  <div id="dala-bridge" phx-hook="DalaHook" style="display:none"></div>
  <%= @inner_content %>
</body>
```

---

## Android timing note

On iOS, `window.dala` (Bridge 1) is injected via `WKUserScript` at
`.atDocumentStart` — before any page JavaScript runs.

On Android, it is injected via `evaluateJavascript` in `WebViewClient.onPageFinished`
— after the page has fully loaded. There is a brief window between
`DOMContentLoaded` and `onPageFinished` where `window.dala` is `undefined`.

In practice this is harmless: `DalaHook` mounts after LiveView connects, which
happens after `onPageFinished`, so Bridge 2 is in place before any user
interaction is possible.

However, if you call `window.dala` during `DOMContentLoaded`, guard it:

```javascript
document.addEventListener("DOMContentLoaded", () => {
  if (window.dala) window.dala.send({ type: "ready" })
})
```

---

## Using the message API

### Receiving JS messages in a LiveView

```elixir
defmodule MyAppWeb.HomeLive do
  use MyAppWeb, :live_view
  use Dala.LiveView  # optional — see below

  def handle_event("dala_message", %{"event" => "button_tapped", "id" => id}, socket) do
    {:noreply, assign(socket, :last_tap, id)}
  end
end
```

`use Dala.LiveView` is optional. It adds a catch-all `handle_event("dala_message", ...)`
clause that returns `{:noreply, socket}`, so unhandled native events do not crash
your LiveView.

**Important:** defining your own `handle_event/3` replaces the catch-all entirely
(Elixir `defoverridable` semantics). If you define `handle_event/3`, add your own
catch-all for events you do not explicitly handle:

```elixir
def handle_event("dala_message", %{"type" => "ping"}, socket) do
  {:noreply, assign(socket, :pinged, true)}
end

# required — without this, unhandled dala_message events raise FunctionClauseError
def handle_event("dala_message", _data, socket), do: {:noreply, socket}
```

### Pushing messages from Elixir to JS

```elixir
push_event(socket, "dala_push", %{type: "theme_changed", value: "dark"})
```

This calls all handlers registered with `window.dala.onMessage(fn)` in your page JS.

### JS side

```javascript
// Send to Elixir
window.dala.send({ event: "button_tapped", id: "submit" })

// Receive from Elixir
window.dala.onMessage(function(data) {
  if (data.type === "theme_changed") applyTheme(data.value)
})
```

---

## Configuring the port

The WebView loads `http://127.0.0.1:PORT/`. Set the port in `dala.exs`:

```elixir
config :dala, liveview_port: 4000
```

`Dala.LiveView.local_url/1` reads this value:

```elixir
Dala.UI.webview(url: Dala.LiveView.local_url("/"))           # http://127.0.0.1:4000/
Dala.UI.webview(url: Dala.LiveView.local_url("/dashboard"))  # http://127.0.0.1:4000/dashboard
```

Use `127.0.0.1` explicitly — not `localhost`. On Android, `localhost` may resolve to the host machine rather than the device's own loopback interface.

### Port conflict warning

LV port 4200 is **global per device**. Two installed Dala LV apps + one running = the second can't bind. Workaround for now: force-stop the squatter. Real fix tracked in `issues.md` #4 (hash bundle id into port).

---

## Troubleshooting

### `handle_event("dala_message", ...)` never fires

The DalaHook has not mounted. Check in order:

1. **Is the bridge element present?** Open your `root.html.heex` and confirm
   `<div id="dala-bridge" phx-hook="DalaHook" ...>` is inside `<body>`.

2. **Is DalaHook registered?** Open `assets/js/app.js` and confirm:
   - `const DalaHook = { mounted() { ... } }` is defined
   - `hooks: {DalaHook}` (or `hooks: {DalaHook, ...}`) is in the `LiveSocket` constructor

3. **Verify at runtime.** Open WebView devtools and run:
   ```javascript
   window.dala.send.toString()
   // Should contain "pushEvent", not "postMessage"
   ```
   If it says `postMessage`, DalaHook has not mounted and you are on Bridge 1.

### Messages arrive in `handle_info({:webview, :message, ...})` instead of `handle_event`

Same root cause as above — `window.dala` is still the native bridge. Fix the
bridge element.

### `window.dala` is undefined

On Android during `DOMContentLoaded` this is expected — see the timing note above.
If it is undefined after the page has fully loaded, the native WebView shim failed
to inject. Check the Android logcat for WebView errors.

### LiveView works in the browser but not in the WebView

The BEAM and Phoenix must both run **on-device**, not on your development Mac.
The WebView resolves `127.0.0.1` to the device's own loopback. Run
`mix dala.deploy` to push the app to the device, then confirm the node is
running with `mix dala.connect`.

### Port mismatch

If the WebView shows a connection error, check that:
- `config :dala, liveview_port:` in `dala.exs` matches the port in `config/dev.exs`
  (`config :my_app, MyAppWeb.Endpoint, http: [port: 4000]`)
- Both values are the same number
