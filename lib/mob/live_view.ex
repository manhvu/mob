defmodule Mob.LiveView do
  @moduledoc """
  Bridge between Phoenix LiveView and the Mob native WebView layer.

  In LiveView mode a Mob project runs a local Phoenix endpoint on the device.
  A `Mob.Screen` wraps the app in a `Mob.UI.webview/1` pointing at
  `http://127.0.0.1:PORT`. LiveView updates flow over the existing WebSocket
  with loopback-speed latency (~1–5 ms).

  The JS bridge shim (injected by `mix mob.enable liveview` into
  `assets/js/app.js`) routes through LiveView hooks instead of the native
  postMessage channels, so the same `window.mob.send` / `window.mob.onMessage`
  API works identically in both plain-WebView and LiveView-mode apps.

  ## Receiving native messages in a LiveView

      defmodule MyAppWeb.HomeLive do
        use MyAppWeb, :live_view
        use Mob.LiveView

        def handle_event("mob_message", %{"type" => "back"}, socket) do
          # user pressed Android back / iOS edge-pan while on this view
          {:noreply, push_navigate(socket, to: ~p"/")}
        end
      end

  `use Mob.LiveView` is optional — it just adds a fallthrough no-op
  `handle_event("mob_message", ...)` so unhandled native events don't crash.

  ## Pushing messages to the WebView JS

      push_event(socket, "mob_push", %{type: "haptic", style: "medium"})

  The `MobHook` registered in `app.js` delivers this to `window.mob.onMessage`
  handlers in the page.

  ## local_url/1

  Use `Mob.LiveView.local_url/1` to build URLs for `Mob.UI.webview/1`:

      Mob.UI.webview(url: Mob.LiveView.local_url("/"))
      Mob.UI.webview(url: Mob.LiveView.local_url("/dashboard"))

  Port is read from `Application.get_env(:mob, :liveview_port)`, defaulting
  to 4000. Set it in `mob.exs`:

      config :mob, liveview_port: 4001
  """

  defmacro __using__(_opts) do
    quote do
      # Fallthrough so unhandled native events don't raise.
      # User-defined handle_event("mob_message", ...) clauses take priority
      # because they are compiled before this catch-all.
      def handle_event("mob_message", _data, socket), do: {:noreply, socket}
      defoverridable handle_event: 3
    end
  end

  @doc """
  Returns a loopback URL for the local Phoenix endpoint at `path`.

  Port defaults to 4000. Override in `mob.exs`:

      config :mob, liveview_port: 4001

  ## Examples

      iex> Mob.LiveView.local_url("/")
      "http://127.0.0.1:4000/"

      iex> Mob.LiveView.local_url("/dashboard")
      "http://127.0.0.1:4000/dashboard"
  """
  def local_url(path \\ "/") do
    port = Application.get_env(:mob, :liveview_port, 4000)
    "http://127.0.0.1:#{port}#{path}"
  end
end
