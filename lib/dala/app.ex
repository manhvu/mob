defmodule Dala.App do
  @moduledoc """
  Behaviour for Dala application entry point.

  ## Usage

      defmodule MyApp do
        use Dala.App

        def navigation(_platform) do
          stack(:home, root: MyApp.HomeScreen)
        end

        def on_start do
          # Pattern-match start_root so failures crash loudly instead of hanging
          {:ok, _pid} = Dala.Screen.start_root(MyApp.HomeScreen)
          # ⚠️ Use secure cookies - never hardcode in production!
          cookie = Dala.Dist.cookie_from_env("MY_APP_DIST_COOKIE", "my_app")
          Dala.Dist.ensure_started(node: :"my_app@127.0.0.1", cookie: cookie)
        end
      end

  `use Dala.App` generates a `start/0` that the BEAM entry point calls. It
  handles all framework initialization (native logger, navigation registry)
  before delegating to `on_start/0`. App code only goes in `on_start/0`.

  ## Navigation

  Implement `navigation/1` to declare the app's navigation structure.
  Use the helper functions `stack/2`, `tab_bar/1`, and `drawer/1`:

      def navigation(:ios),     do: tab_bar([stack(:home, root: HomeScreen), ...])
      def navigation(:android), do: drawer([stack(:home, root: HomeScreen), ...])
      def navigation(_),        do: stack(:home, root: HomeScreen)

  All `name` atoms used in stacks become valid `push_screen` destinations
  without needing to reference modules directly.
  """

  @callback navigation(platform :: atom()) :: map()

  @doc """
  App-specific startup hook. Called by the generated `start/0` after all
  framework initialization is complete.

  Override to start your root screen, configure Erlang distribution,
  set the Logger level, etc. The default implementation is a no-op.
  """
  @callback on_start() :: term()

  @optional_callbacks [on_start: 0]

  defmacro __using__(opts) do
    theme_opts = Keyword.get(opts, :theme, [])

    quote do
      @behaviour Dala.App
      import Dala.App

      @doc """
      Framework entry point — called from the BEAM entry module (e.g.
      `dala_demo.erl`) after OTP applications have started.

      Installs `Dala.NativeLogger` so all Elixir Logger output is routed to
      the platform system log (logcat / NSLog) from this point forward, seeds
      the `Dala.Nav.Registry` from this module's `navigation/1` declarations,
      then calls `on_start/0` for app-specific initialization.

      Do not override — implement `on_start/0` instead.
      """
      def start do
        Dala.NativeLogger.install()

        # Compile theme from options passed to `use Dala.App, theme: [...]`
        # and store it so Dala.Renderer picks it up on every render.
        # Always called — even with [] this seeds the default theme explicitly.
        Dala.Theme.set(unquote(theme_opts))

        case Dala.Nav.Registry.start_link(__MODULE__) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        case Dala.State.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        case Dala.ComponentRegistry.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        # Dala.Device dispatcher + platform fan-out modules. Order matters:
        # the IOS / Android modules must exist before Dala.Device starts,
        # because Dala.Device forwards platform-tagged messages to them.
        case Dala.Device.IOS.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        case Dala.Device.Android.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        case Dala.Device.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        # Adaptive-theme watcher: subscribes to Dala.Device :appearance and
        # re-resolves Dala.Theme on OS color-scheme flips. Started after
        # Dala.Device so the subscribe call has a target.
        case Dala.Theme.AdaptiveWatcher.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        __MODULE__.on_start()
      end

      def on_start, do: :ok

      defoverridable on_start: 0
    end
  end

  # ── Navigation helpers ─────────────────────────────────────────────────────

  @doc """
  Declare a navigation stack.

  `name` is the atom identifier used with `push_screen/2,3`, `pop_to/2`,
  and `reset_to/2,3`. The `:root` option is the module mounted when the stack
  is first entered.

  Options:
  - `:root` (required) — screen module that is the stack's initial screen
  - `:title` — optional display label shown in tabs or drawer entries
  """
  @spec stack(atom(), keyword()) :: map()
  def stack(name, opts) when is_atom(name) and is_list(opts) do
    %{
      type: :stack,
      name: name,
      root: Keyword.fetch!(opts, :root),
      title: Keyword.get(opts, :title)
    }
  end

  @doc """
  Declare a tab bar containing multiple named stacks.

  Each branch must be a `stack/2` map. Renders as a bottom NavigationBar on
  Android and a UITabBarController on iOS.
  """
  @spec tab_bar([map()]) :: map()
  def tab_bar(branches) when is_list(branches) do
    %{type: :tab_bar, branches: branches}
  end

  @doc """
  Declare a side drawer containing multiple named stacks.

  Renders as a ModalNavigationDrawer on Android. iOS uses a custom slide-in
  panel (native UIKit drawer support deferred).
  """
  @spec drawer([map()]) :: map()
  def drawer(branches) when is_list(branches) do
    %{type: :drawer, branches: branches}
  end

  @doc """
  Declare a screen module for use in navigation.

  This is a convenience function that can be used in `navigation/1` to
  register screens. The screen module must implement `Dala.Screen` behaviour.

  Example:
      def navigation(_) do
        screens([
          MyApp.HomeScreen,
          MyApp.SettingsScreen
        ])
        stack(:home, root: MyApp.HomeScreen)
      end
  """
  @spec screens([module()]) :: :ok
  def screens(screen_modules) when is_list(screen_modules) do
    Enum.each(screen_modules, fn mod ->
      unless Code.ensure_loaded?(mod) and function_exported?(mod, :render, 1) do
        raise ArgumentError, "#{inspect(mod)} is not a valid Dala.Screen module"
      end
    end)

    :ok
  end
end
