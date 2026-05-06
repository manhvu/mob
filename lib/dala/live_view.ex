defmodule Dala.LiveView do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  Bridge between Phoenix LiveView and the Dala native WebView.

  ## Overview

  LiveView mode lets you ship a dalaile app using only Phoenix LiveView — no
  native UI code required. Dala runs a local Phoenix endpoint on the device and
  wraps it in a native WebView. LiveView updates travel over the existing
  WebSocket at loopback speed (~1–5 ms).

  Enable it with:

      mix dala.enable liveview

  See `guides/liveview.md` for the full setup walkthrough.

  ---

  ## The two-bridge architecture

  This is the most important thing to understand when working in LiveView mode.
  There are **two separate JavaScript bridges** for communicating between JS and
  Elixir, and they are mutually exclusive.

  ### Bridge 1 — The native bridge (always present)

  The native WebView (iOS `WKWebView` / Android `WebView`) injects a
  `window.dala` object into every page it loads. This object routes calls
  through the NIF, bypassing LiveView entirely:

  | Direction | How it works |
  |---|---|
  | JS → Elixir | `window.dala.send(data)` → `postMessage` / `JavascriptInterface` → NIF → `dala_deliver_webview_message` → `handle_info({:webview, :message, data}, socket)` in your `Dala.Screen` |
  | Elixir → JS | `Dala.WebView.post_message(socket, data)` → NIF → `evaluateJavascript("window.dala._dispatch(...)")` → all registered `onMessage` handlers |

  **iOS** injects the shim via `WKUserScript` at `.atDocumentStart` — before
  any page JS runs.

  **Android** injects it via `evaluateJavascript` in `WebViewClient.onPageFinished`
  — after the page has loaded. See the Android timing note below.

  ### Bridge 2 — The LiveView bridge (active after dalaHook mounts)

  When `dalaHook` mounts it *replaces* `window.dala` with a LiveView-backed
  version that routes over the Phoenix WebSocket:

  | Direction | How it works |
  |---|---|
  | JS → Elixir | `window.dala.send(data)` → `this.pushEvent("dala_message", data)` → `handle_event("dala_message", data, socket)` in your LiveView |
  | Elixir → JS | `push_event(socket, "dala_push", data)` → `this.handleEvent("dala_push", handler)` → all registered `onMessage` handlers |

  The `_dispatch` function is a no-op in LiveView mode — native `post_message`
  calls from Elixir still work at the NIF level but the LiveView path is
  preferred.

  ---

  ## Why a DOM element is required (the non-obvious part)

  `mix dala.enable liveview` injects `dalaHook` into `assets/js/app.js` and
  registers it with `LiveSocket`. This is necessary but **not sufficient**.

  Phoenix LiveView hooks only execute their `mounted()` callback when:

  1. A DOM element with `phx-hook="dalaHook"` exists in the rendered page, AND
  2. The LiveView WebSocket has connected.

  Without a matching DOM element the hook never fires, `window.dala` is never
  replaced, and all JS messages silently route through the native NIF bridge
  instead of LiveView. `handle_event/3` in your LiveView will never be called.

  `mix dala.enable liveview` patches `root.html.heex` to add this element:

      <div id="dala-bridge" phx-hook="DalaHook" style="display:none"></div>

  It is placed immediately after the opening `<body>` tag so it mounts as
  early as possible. If you set up LiveView mode manually and something is not
  working, the missing bridge element is the most likely cause.

  ### If root.html.heex is not found

  `mix dala.enable liveview` will print the element and ask you to add it
  manually if it cannot find `root.html.heex`. Add it inside `<body>` in
  whichever layout file wraps your entire app.

  ---

  ## Android timing note

  On Android, `window.dala` is injected after `onPageFinished`. There is a brief
  window between `DOMContentLoaded` and `onPageFinished` where `window.dala` is
  `undefined`. The dalaHook mounts after LiveView connects, which is also after
  `onPageFinished`, so in practice the bridges are sequenced correctly. However,
  if you call `window.dala` during `DOMContentLoaded`, guard it:

      document.addEventListener("DOMContentLoaded", () => {
        if (window.dala) window.dala.send({ type: "ready" })
      })

  iOS does not have this issue — `window.dala` is available before any JS runs.

  ---

  ## Message API

  The `window.dala` API is identical in both bridge modes. Your JS code does not
  need to know which bridge is active:

      // Send a message to Elixir
      window.dala.send({ event: "button_tapped", id: "submit" })

      // Receive messages from Elixir
      window.dala.onMessage(function(data) {
        console.log("received:", data)
      })

  ### Elixir side — receiving JS messages in a LiveView

      defmodule MyAppWeb.HomeLive do
        use MyAppWeb, :live_view
        use Dala.LiveView   # optional: adds a no-op fallthrough for dala_message

        def handle_event("dala_message", %{"event" => "button_tapped", "id" => id}, socket) do
          {:noreply, assign(socket, :last_tap, id)}
        end
      end

  `use Dala.LiveView` is optional. It adds a catch-all `handle_event("dala_message", ...)`
  clause so unhandled native events do not crash your LiveView.

  **Important:** defining your own `handle_event/3` replaces the catch-all entirely
  (`defoverridable` semantics). If you define `handle_event/3`, add your own
  catch-all for events you do not handle:

      def handle_event("dala_message", _data, socket), do: {:noreply, socket}

  ### Elixir side — pushing messages to JS

      push_event(socket, "dala_push", %{type: "theme_changed", value: "dark"})

  This calls all handlers registered with `window.dala.onMessage(fn)` in JS.

  ---

  ## local_url/1

  Use `Dala.LiveView.local_url/1` to build the loopback URL for `Dala.UI.webview/1`:

      Dala.UI.webview(url: Dala.LiveView.local_url("/"))
      Dala.UI.webview(url: Dala.LiveView.local_url("/dashboard"))

  The port is read from `Application.get_env(:dala, :liveview_port)`, defaulting
  to 4000. Set it in `dala.exs` (created by `mix dala.enable liveview`):

      config :dala, liveview_port: 4000

  ---

  ## Troubleshooting

  **`handle_event("dala_message", ...)` never fires**

  The dalaHook is not mounting. Check:
  1. `root.html.heex` has `<div id="dala-bridge" phx-hook="DalaHook" style="display:none"></div>` inside `<body>`
  2. `app.js` contains `const DalaHook = { ... }` and `hooks: {DalaHook}` in the LiveSocket config
  3. Open browser devtools in the WebView and confirm `window.dala.send` is a function that calls `pushEvent`, not `postMessage`

  **Messages arrive in `handle_info({:webview, :message, ...})` instead of `handle_event`**

  `window.dala` is still pointing at the native bridge. The dalaHook has not
  mounted. See point 1 above.

  **`window.dala` is undefined on Android during `DOMContentLoaded`**

  Expected — see the Android timing note above. Guard the call or move it to
  after LiveView connects.

  **LiveView works in the browser but not in the WebView**

  Ensure Phoenix is binding to `127.0.0.1` (not just `localhost`) and that
  `liveview_port` in `dala.exs` matches the port Phoenix is listening on. The
  WebView resolves `127.0.0.1` to the device's own loopback — not the Mac's.
  The BEAM and Phoenix must both run on the device (i.e., you ran
  `mix dala.deploy` and the app is running on-device, not the dev server on
  your Mac).
  """

  defmacro __using__(_opts) do
    quote do
      # Catch-all so unhandled native events don't raise in the LiveView.
      # Catch-all so unhandled dala_message events don't raise.
      # NOTE: defoverridable means defining any handle_event/3 in the using
      # module replaces this entirely. Users must add their own catch-all if
      # they define handle_event/3 and want unmatched events ignored.
      def handle_event("dala_message", _data, socket), do: {:noreply, socket}
      defoverridable handle_event: 3
    end
  end

  @doc """
  Call this from your app's start/0 to suppress dev-tool warnings on-device.

  Both `:esbuild` and `:tailwind` are dev-time tools that get started on-device
  because they're listed as runtime applications. This function sets dummy
  version configs so they don't warn about missing configuration.

  ## Usage

  In your `lib/my_app/app.ex` (generated by `mix dala.new --liveview`):

      def start do
        # Suppress esbuild/tailwind warnings on-device
        Dala.LiveView.suppress_dev_tool_warnings()
        ...
      end
  """
  def suppress_dev_tool_warnings do
    # Only suppress on dalaile platforms where these tools can't possibly run
    if Dala.Native.platform() in [:android, :ios] do
      case Application.get_env(:esbuild, :version) do
        nil -> Application.put_env(:esbuild, :version, "0.25.0")
        _ -> :ok
      end

      case Application.get_env(:tailwind, :version) do
        nil -> Application.put_env(:tailwind, :version, "3.4.6")
        _ -> :ok
      end
    end

    :ok
  end

  @doc """
  Returns a loopback URL for the local Phoenix endpoint at `path`.

  The WebView on the device loads this URL. Because both the BEAM and Phoenix
  run on-device, `127.0.0.1` resolves correctly. Do not use `localhost` — on
  Android it may resolve to the host machine rather than the device loopback.

  Port defaults to a hash-based allocation to avoid collisions between multiple
  Dala LiveView apps on the same device. The hash maps the app name to a port
  in the range 4200-4999, giving low collision probability.

  Override in `dala.exs`:

      config :dala, liveview_port: 4001

  Or set the `dala_LIVEVIEW_PORT` environment variable to force a specific port.
  """
  @spec local_url(String.t()) :: String.t()
  def local_url(path \\ "/") do
    port = liveview_port()
    "http://127.0.0.1:#{port}#{path}"
  end

  # Determine the LiveView port with the following priority:
  # 1. Environment variable dala_LIVEVIEW_PORT (for runtime override)
  # 2. Application config :dala, :liveview_port
  # 3. Hash-based default (4200-4999 range)
  defp liveview_port do
    case System.get_env("dala_LIVEVIEW_PORT") do
      nil ->
        case Application.get_env(:dala, :liveview_port) do
          nil -> default_port()
          port -> port
        end

      port_str ->
        String.to_integer(port_str)
    end
  end

  # Generate a deterministic port in the range 4200-4999 based on the app name.
  # This avoids collisions when multiple Dala LV apps are installed on the same device.
  # With 800 ports and assuming 5 apps, collision probability is ~2.5% (birthday paradox).
  defp default_port do
    # Try to get the app name from the Mix project or use a fallback
    app_name =
      case Application.get_application(__MODULE__) do
        nil -> "dala_default"
        app -> Atom.to_string(app)
      end

    4200 + rem(:erlang.phash2(app_name), 800)
  end
end
