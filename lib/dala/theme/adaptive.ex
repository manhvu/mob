defmodule Dala.Theme.Adaptive do
  @moduledoc """
  Theme that follows the OS-level light / dark setting.

  At call time `theme/0` reads `Dala.Theme.color_scheme/0` and returns
  `Dala.Theme.Light.theme/0` or `Dala.Theme.Dark.theme/0`. Built for
  outdoor working users — sun-readable in daytime, eye-friendly at night.

  ## Usage

      defmodule MyApp do
        use Dala.App, theme: Dala.Theme.Adaptive
      end

  ## Reactive switching

  `Dala.Theme.set/1` snapshots the theme at call time, so toggling the OS
  appearance after the app has started does not auto-update the rendered
  theme. To re-evaluate, call `Dala.Theme.set(Dala.Theme.Adaptive)` again
  (e.g. in response to a foreground / lifecycle event, or after a planned
  `:color_scheme_changed` device event in a future version).
  """

  @doc "Returns the Light or Dark theme struct based on the current OS appearance."
  @spec theme() :: Dala.Theme.t()
  def theme do
    case Dala.Theme.color_scheme() do
      :dark -> Dala.Theme.Dark.theme()
      _ -> Dala.Theme.Light.theme()
    end
  end
end
