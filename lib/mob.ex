defmodule Mob do
  @moduledoc """
  Mob — BEAM-on-device mobile framework for Elixir.

  OTP runs on the device. Screens are GenServers. The UI is rendered by
  Compose (Android) and SwiftUI (iOS) via a thin NIF. No server required.

  ## Quick start

      defmodule MyApp.HomeScreen do
        use Mob.Screen

        def mount(_params, _session, socket) do
          {:ok, Mob.Socket.assign(socket, :title, "Hello, Mob!")}
        end

        def render(assigns) do
          %{
            type:  :column,
            props: %{padding: :space_md},
            children: [
              %{type: :text, props: %{text: assigns.title, text_size: :xl}, children: []}
            ]
          }
        end
      end

  ## Modules

  - `Mob.App` — app entry point and navigation declaration
  - `Mob.Screen` — screen behaviour and GenServer wrapper
  - `Mob.Socket` — assigns and navigation API
  - `Mob.Theme` — design token system
  - `Mob.Renderer` — component tree serialisation
  - `Mob.Test` — live device inspection and testing helpers

  See the [Getting Started](guides/getting_started.html) guide to create your
  first app. See [Architecture & Prior Art](guides/architecture.html) for how
  Mob compares to LiveView Native, Elixir Desktop, React Native, Flutter, and
  native development.
  """

  defdelegate assign(socket, key, value), to: Mob.Socket
  defdelegate assign(socket, kw), to: Mob.Socket
end
