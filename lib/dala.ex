defmodule Dala do
  @moduledoc """
  Dala — BEAM-on-device dalaile framework for Elixir.

  OTP runs on the device. Screens are GenServers. The UI is rendered by
  Compose (Android) and SwiftUI (iOS) via a thin NIF. No server required.

  ## Quick start

      defmodule MyApp.HomeScreen do
        use Dala.Screen

        def mount(_params, _session, socket) do
          {:ok, Dala.Socket.assign(socket, :title, "Hello, Dala!")}
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

  - `Dala.App` — app entry point and navigation declaration
  - `Dala.Screen` — screen behaviour and GenServer wrapper
  - `Dala.Socket` — assigns and navigation API
  - `Dala.Theme` — design token system
  - `Dala.Renderer` — component tree serialisation
  - `Dala.Test` — live device inspection and testing helpers

  See the [Getting Started](guides/getting_started.html) guide to create your
  first app. See [Architecture & Prior Art](guides/architecture.html) for how
  Dala compares to LiveView Native, Elixir Desktop, React Native, Flutter, and
  native development.
  """

  defdelegate assign(socket, key, value), to: Dala.Socket
  defdelegate assign(socket, kw), to: Dala.Socket
end
