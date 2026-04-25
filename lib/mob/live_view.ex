defmodule Mob.LiveView do
  @moduledoc """
  Bridge between Phoenix LiveView and the Mob native WebView.

  ## Overview

  LiveView mode lets you ship a mobile app using only Phoenix LiveView — no
  native UI code required. Mob runs a local Phoenix endpoint on the device and
  wraps it in a native WebView. LiveView updates travel over the existing
  WebSocket at loopback speed (~1–5 ms).

  Enable it with:

      mix mob.enable liveview

  See `guides/liveview.md` for the full setup walkthrough.

  ---

  ## The two-bridge architecture

  This is the most important thing to understand when working in LiveView mode.
  There are **two separate JavaScript bridges** for communicating between JS and
  Elixir, and they are mutually exclusive.

  ### Bridge 1 — The native bridge (always present)

  The native WebView (iOS `WKWebView` / Android `WebView`) injects a
  `window.mob` object into every page it loads. This object routes calls
  through the NIF, bypassing LiveView entirely:

  | Direction | How it works |
  |---|---|
  | JS → Elixir | `window.mob.send(data)` → `postMessage` / `JavascriptInterface` → NIF → `mob_deliver_webview_message` → `handle_info({:webview, :message, data}, socket)` in your `Mob.Screen` |
  | Elixir → JS | `Mob.WebView.post_message(socket, data)` → NIF → `evaluateJavascript("window.mob._dispatch(...)")` → all registered `onMessage` handlers |

  **iOS** injects the shim via `WKUserScript` at `.atDocumentStart` — before
  any page JS runs.

  **Android** injects it via `evaluateJavascript` in `WebViewClient.onPageFinished`
  — after the page has loaded. See the Android timing note below.

  ### Bridge 2 — The LiveView bridge (active after MobHook mounts)

  When `MobHook` mounts it *replaces* `window.mob` with a LiveView-backed
  version that routes over the Phoenix WebSocket:

  | Direction | How it works |
  |---|---|
  | JS → Elixir | `window.mob.send(data)` → `this.pushEvent("mob_message", data)` → `handle_event("mob_message", data, socket)` in your LiveView |
  | Elixir → JS | `push_event(socket, "mob_push", data)` → `this.handleEvent("mob_push", handler)` → all registered `onMessage` handlers |

  The `_dispatch` function is a no-op in LiveView mode — native `post_message`
  calls from Elixir still work at the NIF level but the LiveView path is
  preferred.

  ---

  ## Why a DOM element is required (the non-obvious part)

  `mix mob.enable liveview` injects `MobHook` into `assets/js/app.js` and
  registers it with `LiveSocket`. This is necessary but **not sufficient**.

  Phoenix LiveView hooks only execute their `mounted()` callback when:

  1. A DOM element with `phx-hook="MobHook"` exists in the rendered page, AND
  2. The LiveView WebSocket has connected.

  Without a matching DOM element the hook never fires, `window.mob` is never
  replaced, and all JS messages silently route through the native NIF bridge
  instead of LiveView. `handle_event/3` in your LiveView will never be called.

  `mix mob.enable liveview` patches `root.html.heex` to add this element:

      <div id="mob-bridge" phx-hook="MobHook" style="display:none"></div>

  It is placed immediately after the opening `<body>` tag so it mounts as
  early as possible. If you set up LiveView mode manually and something is not
  working, the missing bridge element is the most likely cause.

  ### If root.html.heex is not found

  `mix mob.enable liveview` will print the element and ask you to add it
  manually if it cannot find `root.html.heex`. Add it inside `<body>` in
  whichever layout file wraps your entire app.

  ---

  ## Android timing note

  On Android, `window.mob` is injected after `onPageFinished`. There is a brief
  window between `DOMContentLoaded` and `onPageFinished` where `window.mob` is
  `undefined`. The MobHook mounts after LiveView connects, which is also after
  `onPageFinished`, so in practice the bridges are sequenced correctly. However,
  if you call `window.mob` during `DOMContentLoaded`, guard it:

      document.addEventListener("DOMContentLoaded", () => {
        if (window.mob) window.mob.send({ type: "ready" })
      })

  iOS does not have this issue — `window.mob` is available before any JS runs.

  ---

  ## Message API

  The `window.mob` API is identical in both bridge modes. Your JS code does not
  need to know which bridge is active:

      // Send a message to Elixir
      window.mob.send({ event: "button_tapped", id: "submit" })

      // Receive messages from Elixir
      window.mob.onMessage(function(data) {
        console.log("received:", data)
      })

  ### Elixir side — receiving JS messages in a LiveView

      defmodule MyAppWeb.HomeLive do
        use MyAppWeb, :live_view
        use Mob.LiveView   # optional: adds a no-op fallthrough for mob_message

        def handle_event("mob_message", %{"event" => "button_tapped", "id" => id}, socket) do
          {:noreply, assign(socket, :last_tap, id)}
        end
      end

  `use Mob.LiveView` is optional. It adds a catch-all `handle_event("mob_message", ...)`
  clause so unhandled native events do not crash your LiveView.

  **Important:** defining your own `handle_event/3` replaces the catch-all entirely
  (`defoverridable` semantics). If you define `handle_event/3`, add your own
  catch-all for events you do not handle:

      def handle_event("mob_message", _data, socket), do: {:noreply, socket}

  ### Elixir side — pushing messages to JS

      push_event(socket, "mob_push", %{type: "theme_changed", value: "dark"})

  This calls all handlers registered with `window.mob.onMessage(fn)` in JS.

  ---

  ## local_url/1

  Use `Mob.LiveView.local_url/1` to build the loopback URL for `Mob.UI.webview/1`:

      Mob.UI.webview(url: Mob.LiveView.local_url("/"))
      Mob.UI.webview(url: Mob.LiveView.local_url("/dashboard"))

  The port is read from `Application.get_env(:mob, :liveview_port)`, defaulting
  to 4000. Set it in `mob.exs` (created by `mix mob.enable liveview`):

      config :mob, liveview_port: 4000

  ---

  ## Troubleshooting

  **`handle_event("mob_message", ...)` never fires**

  The MobHook is not mounting. Check:
  1. `root.html.heex` has `<div id="mob-bridge" phx-hook="MobHook" style="display:none"></div>` inside `<body>`
  2. `app.js` contains `const MobHook = { ... }` and `hooks: {MobHook}` in the LiveSocket config
  3. Open browser devtools in the WebView and confirm `window.mob.send` is a function that calls `pushEvent`, not `postMessage`

  **Messages arrive in `handle_info({:webview, :message, ...})` instead of `handle_event`**

  `window.mob` is still pointing at the native bridge. The MobHook has not
  mounted. See point 1 above.

  **`window.mob` is undefined on Android during `DOMContentLoaded`**

  Expected — see the Android timing note above. Guard the call or move it to
  after LiveView connects.

  **LiveView works in the browser but not in the WebView**

  Ensure Phoenix is binding to `127.0.0.1` (not just `localhost`) and that
  `liveview_port` in `mob.exs` matches the port Phoenix is listening on. The
  WebView resolves `127.0.0.1` to the device's own loopback — not the Mac's.
  The BEAM and Phoenix must both run on the device (i.e., you ran
  `mix mob.deploy` and the app is running on-device, not the dev server on
  your Mac).
  """

  defmacro __using__(_opts) do
    quote do
      # Catch-all so unhandled native events don't raise in the LiveView.
      # Catch-all so unhandled mob_message events don't raise.
      # NOTE: defoverridable means defining any handle_event/3 in the using
      # module replaces this entirely. Users must add their own catch-all if
      # they define handle_event/3 and want unmatched events ignored.
      def handle_event("mob_message", _data, socket), do: {:noreply, socket}
      defoverridable handle_event: 3
    end
  end

  @doc """
  Returns a loopback URL for the local Phoenix endpoint at `path`.

  The WebView on the device loads this URL. Because both the BEAM and Phoenix
  run on-device, `127.0.0.1` resolves correctly. Do not use `localhost` — on
  Android it may resolve to the host machine rather than the device loopback.

  Port defaults to 4000. Override in `mob.exs`:

      config :mob, liveview_port: 4001

  ## Examples

      iex> Mob.LiveView.local_url("/")
      "http://127.0.0.1:4000/"

      iex> Mob.LiveView.local_url("/dashboard")
      "http://127.0.0.1:4000/dashboard"
  """
  @spec local_url(String.t()) :: String.t()
  def local_url(path \\ "/") do
    port = Application.get_env(:mob, :liveview_port, 4000)
    "http://127.0.0.1:#{port}#{path}"
  end
end
