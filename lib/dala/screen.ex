defmodule Dala.Screen do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  Screen behaviour and Spark DSL entry point.

  ## Usage

      defmodule MyApp.CounterScreen do
        use Dala.Screen

        attributes do
          attribute :count, :integer, default: 0
        end

        screen do
          name :counter
          column do
            gap :space_sm
            text "Count: @count"
            button "Increment", on_tap: :increment
          end
        end

        def handle_event(:increment, _params, socket) do
          {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
        end
      end

  ## Starting a screen

      Dala.Screen.start_root(MyApp.CounterScreen, %{})

  ## Dispatching events

      Dala.Screen.dispatch(pid, "increment", %{})
  """

  # Set up Spark DSL - makes Dala.Screen a Spark extension module
  use Spark.Dsl.Extension, extensions: [Dala.Spark.Dsl]

  # The __using__ macro now just needs to call `use Dala.Screen`
  defmacro __using__(_opts) do
    quote do
      use Dala.Spark.Dsl
      @behaviour Dala.Screen
      import Dala.Sigil

      # Default handle_info implementation
      def handle_info(_message, socket), do: {:noreply, socket}

      def terminate(_reason, _socket), do: :ok

      def handle_event(event, _params, _socket) do
        raise "unhandled event #{inspect(event)} in #{inspect(__MODULE__)}. " <>
                "Add a handle_event/3 clause to handle it."
      end

      defoverridable handle_info: 2, terminate: 2, handle_event: 3
    end
  end

  # ── GenServer wrapper ─────────────────────────────────────────────────────

  use GenServer

  @doc """
  Start a screen process linked to the calling process.

  `params` is passed as the first argument to `mount/3`.
  """
  @spec start_link(module(), map(), keyword()) :: GenServer.on_start()
  def start_link(screen_module, params, opts \\ []) do
    GenServer.start_link(__MODULE__, {screen_module, params, :no_render, :android}, opts)
  end

  @doc """
  Return the module of the currently active screen in the navigation stack.
  Intended for testing and debugging.
  """
  @spec get_current_module(pid()) :: module()
  def get_current_module(pid) do
    GenServer.call(pid, :get_current_module)
  end

  @doc """
  Return the navigation history (list of `{module, socket}` pairs, head = most recent).
  Intended for testing and debugging.
  """
  @spec get_nav_history(pid()) :: [{module(), Dala.Socket.t()}]
  def get_nav_history(pid) do
    GenServer.call(pid, :get_nav_history)
  end

  @doc """
  Start a screen as the root UI screen. Calls mount, renders the component tree
  via `Dala.Renderer`, and calls `set_root` on the resulting view.

  This is the main entry point for production use. `start_link/2` is for tests
  (no NIF calls).
  """
  @spec start_root(module(), map(), keyword()) :: GenServer.on_start()
  def start_root(screen_module, params \\ %{}, opts \\ []) do
    platform = Dala.Native.platform()
    GenServer.start_link(__MODULE__, {screen_module, params, :render, platform}, opts)
  end

  @doc """
  Dispatch a UI event to the screen process. Returns `:ok` synchronously once
  the event has been processed and the state updated.
  """
  @spec dispatch(pid(), String.t(), map()) :: :ok
  def dispatch(pid, event, params) do
    GenServer.call(pid, {:event, event, params})
  end

  @doc """
  Return the current socket state of a running screen.
  Intended for testing and debugging — not for production app logic.
  """
  @spec get_socket(pid()) :: any()
  def get_socket(pid) do
    GenServer.call(pid, :get_socket)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl GenServer
  def init({screen_module, params, render_mode, platform}) do
    socket = Dala.Socket.new(screen_module, platform: platform)

    # Register under :dala_screen so C-layer dala_handle_back() can find us.
    # Only in :render mode (production); tests use :no_render and run without a NIF.
    if render_mode == :render, do: Process.register(self(), :dala_screen)

    socket =
      if render_mode == :render do
        {t, r, b, l} = Dala.Native.safe_area()
        Dala.Socket.assign(socket, :safe_area, %{top: t, right: r, bottom: b, left: l})
      else
        Dala.Socket.assign(socket, :safe_area, %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0})
      end

    case screen_module.mount(params, %{}, socket) do
      {:ok, mounted_socket} ->
        socket =
          if render_mode == :render do
            # Check for a notification that launched the app from a killed state.
            # Send it to self so it arrives via handle_info after init returns,
            # consistent with foreground notification delivery.
            case Dala.Native.take_launch_notification() do
              :none -> :ok
              json -> send(self(), {:dala_launch_notification, json})
            end

            do_render(screen_module, mounted_socket)
          else
            mounted_socket
          end

        {:ok, {screen_module, socket, [], render_mode}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:event, event, params}, _from, {module, socket, nav_history, render_mode}) do
    case module.handle_event(event, params, socket) do
      {:noreply, new_socket} ->
        {module, new_socket, nav_history, transition} =
          apply_nav_action(module, new_socket, nav_history)

        new_socket =
          if render_mode == :render do
            do_render(module, new_socket, transition)
          else
            new_socket
          end

        {:reply, :ok, {module, new_socket, nav_history, render_mode}}

      {:reply, _response, new_socket} ->
        {module, new_socket, nav_history, transition} =
          apply_nav_action(module, new_socket, nav_history)

        new_socket =
          if render_mode == :render do
            do_render(module, new_socket, transition)
          else
            new_socket
          end

        {:reply, :ok, {module, new_socket, nav_history, render_mode}}
    end
  end

  @doc """
  Apply a navigation action directly. Used by `Dala.Test` to drive navigation
  programmatically without needing a UI event. Synchronous — the caller blocks
  until the navigation (and re-render, in production mode) completes.

  Valid actions mirror the `Dala.Socket` navigation functions:
  - `{:push, dest, params}` — push a new screen
  - `{:pop}` — pop to the previous screen
  - `{:pop_to, dest}` — pop to a specific screen in history
  - `{:pop_to_root}` — pop to the root of the current stack
  - `{:reset, dest, params}` — replace the entire nav stack
  """
  def handle_call({:navigate, nav_action}, _from, {module, socket, nav_history, render_mode}) do
    socket = Dala.Socket.put_dala(socket, :nav_action, nav_action)

    {new_module, new_socket, new_history, transition} =
      apply_nav_action(module, socket, nav_history)

    new_socket =
      if render_mode == :render do
        do_render(new_module, new_socket, transition)
      else
        new_socket
      end

    {:reply, :ok, {new_module, new_socket, new_history, render_mode}}
  end

  def handle_call(:get_socket, _from, {_module, socket, _nav_history, _mode} = state) do
    {:reply, socket, state}
  end

  def handle_call(:inspect, _from, {module, socket, nav_history, _mode} = state) do
    tree = module.render(socket.assigns)

    info = %{
      screen: module,
      assigns: socket.assigns,
      nav_history: Enum.map(nav_history, fn {mod, _} -> mod end),
      tree: tree
    }

    {:reply, info, state}
  end

  def handle_call(:get_current_module, _from, {module, _socket, _nav_history, _mode} = state) do
    {:reply, module, state}
  end

  def handle_call(:get_nav_history, _from, {_module, _socket, nav_history, _mode} = state) do
    {:reply, nav_history, state}
  end

  # Notification that launched the app from a killed state.
  # Decoded from JSON and re-dispatched as the standard {:notification, map} message.
  # Hot-reload trigger sent by dala_dev after a dist push. Re-render with current code.
  @impl GenServer
  def handle_cast(:__dala_hot_reload__, {module, socket, nav_history, render_mode}) do
    new_socket =
      if render_mode == :render do
        do_render(module, socket, :hot_reload)
      else
        socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode}}
  end

  @impl GenServer
  def handle_info({:dala_launch_notification, json}, {module, socket, nav_history, render_mode}) do
    notif = decode_notification_json(json)
    handle_info({:notification, notif}, {module, socket, nav_history, render_mode})
  end

  # Android file/camera/photo/scan results arrive as {:dala_file_result, event, sub, json_binary}.
  # Decode the JSON and re-dispatch as the user-facing event tuple.
  def handle_info({:dala_file_result, event, sub, json_binary}, state) do
    event_atom = String.to_atom(event)
    sub_atom = String.to_atom(sub)

    items =
      case :json.decode(json_binary) do
        list when is_list(list) ->
          Enum.map(list, fn item when is_map(item) ->
            Map.new(item, fn {k, v} -> {String.to_atom(k), v} end)
          end)

        _ ->
          []
      end

    msg =
      case {event_atom, sub_atom} do
        {:camera, :photo} ->
          {:camera, :photo, List.first(items) || %{}}

        {:camera, :video} ->
          {:camera, :video, List.first(items) || %{}}

        {:camera, :cancelled} ->
          {:camera, :cancelled}

        {:photos, :picked} ->
          {:photos, :picked, items}

        {:files, :picked} ->
          {:files, :picked, items}

        {:audio, :recorded} ->
          {:audio, :recorded, List.first(items) || %{}}

        {:storage, :saved_to_library} ->
          item = List.first(items) || %{}
          {:storage, :saved_to_library, item[:path]}

        {:scan, :result} ->
          item = List.first(items) || %{}
          {:scan, :result, %{type: item[:type] |> to_atom_safe(), value: item[:value]}}

        _ ->
          {event_atom, sub_atom, items}
      end

    handle_info(msg, state)
  end

  # System back gesture (Android hardware/swipe, iOS edge-pan).
  # Handled here — before the user's handle_info — so every screen gets back
  # navigation for free without implementing anything.
  # If a WebView is present and has internal history, navigate within it first
  # before popping the Dala nav stack.
  def handle_info({:dala, :back}, {module, socket, nav_history, render_mode}) do
    if render_mode == :render && Dala.Native.webview_can_go_back() do
      Dala.Native.webview_go_back()
      {:noreply, {module, socket, nav_history, render_mode}}
    else
      {module, new_socket, new_history, transition} =
        if nav_history == [] do
          if render_mode == :render, do: Dala.Native.exit_app()
          {module, socket, [], :none}
        else
          apply_nav_action(module, Dala.Socket.put_dala(socket, :nav_action, {:pop}), nav_history)
        end

      new_socket =
        if render_mode == :render do
          do_render(module, new_socket, transition)
        else
          new_socket
        end

      {:noreply, {module, new_socket, new_history, render_mode}}
    end
  end

  # List row selected — intercept before the user's handle_info and convert to
  # a plain {:select, id, index} message so screens don't need to know about
  # the internal {:tap, {:list, ...}} tag format.
  def handle_info({:tap, {:list, id, :select, index}}, {module, socket, nav_history, render_mode}) do
    {:noreply, new_socket} = module.handle_info({:select, id, index}, socket)

    {module, new_socket, nav_history, transition} =
      apply_nav_action(module, new_socket, nav_history)

    new_socket =
      if render_mode == :render do
        do_render(module, new_socket, transition)
      else
        new_socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode}}
  end

  # A component's state changed — re-render so the native view gets fresh props.
  def handle_info({:component_changed, _id, _module}, {module, socket, nav_history, render_mode}) do
    new_socket =
      if render_mode == :render do
        do_render(module, socket)
      else
        socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode}}
  end

  def handle_info(message, {module, socket, nav_history, render_mode}) do
    {:noreply, new_socket} = module.handle_info(message, socket)

    {module, new_socket, nav_history, transition} =
      apply_nav_action(module, new_socket, nav_history)

    new_socket =
      if render_mode == :render do
        do_render(module, new_socket, transition)
      else
        new_socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode}}
  end

  defp to_atom_safe(nil), do: :qr
  defp to_atom_safe(s) when is_binary(s), do: String.to_atom(s)
  defp to_atom_safe(a) when is_atom(a), do: a

  @impl GenServer
  def terminate(reason, {module, socket, _nav_history, _render_mode}) do
    module.terminate(reason, socket)
  end

  # ── Navigation ────────────────────────────────────────────────────────────

  # Inspect the socket's nav_action and execute it, returning
  # {new_module, new_socket, new_nav_history, transition}.
  defp apply_nav_action(module, socket, nav_history) do
    case socket.__dala__.nav_action do
      nil ->
        {module, socket, nav_history, :none}

      {:push, dest, params} ->
        new_module = resolve_module(dest)
        platform = socket.__dala__.platform

        new_base =
          Dala.Socket.new(new_module, platform: platform)
          |> Dala.Socket.assign(:safe_area, socket.assigns.safe_area)

        {:ok, mounted} = new_module.mount(params, %{}, new_base)
        saved = {module, clear_nav_action(socket)}
        {new_module, mounted, [saved | nav_history], :push}

      {:pop} ->
        case nav_history do
          [{prev_module, prev_socket} | rest] ->
            {prev_module, prev_socket, rest, :pop}

          [] ->
            {module, clear_nav_action(socket), [], :none}
        end

      {:pop_to_root} ->
        case Enum.reverse(nav_history) do
          [{root_module, root_socket} | _] ->
            {root_module, root_socket, [], :pop}

          [] ->
            {module, clear_nav_action(socket), [], :none}
        end

      {:pop_to, dest} ->
        target = resolve_module(dest)

        case pop_to_module(nav_history, target) do
          {:found, prev_module, prev_socket, rest} ->
            {prev_module, prev_socket, rest, :pop}

          :not_found ->
            {module, clear_nav_action(socket), nav_history, :none}
        end

      {:reset, dest, params} ->
        new_module = resolve_module(dest)
        platform = socket.__dala__.platform

        new_base =
          Dala.Socket.new(new_module, platform: platform)
          |> Dala.Socket.assign(:safe_area, socket.assigns.safe_area)

        {:ok, mounted} = new_module.mount(params, %{}, new_base)
        {new_module, mounted, [], :reset}

      {:switch_tab, _tab} ->
        # Tab switching is handled renderer-side; clear the action.
        {module, clear_nav_action(socket), nav_history, :none}
    end
  end

  defp resolve_module(dest) when is_atom(dest) do
    case Code.ensure_loaded(dest) do
      {:module, ^dest} ->
        # dest is a loaded module — use it directly
        dest

      _ ->
        # dest is a registered screen name atom — look up in registry
        case Dala.Nav.Registry.lookup(dest) do
          {:ok, module} ->
            module

          {:error, :not_found} ->
            raise ArgumentError,
                  "Dala.Screen: unknown navigation destination #{inspect(dest)}. " <>
                    "Register it via Dala.Nav.Registry.register/2 or declare it in " <>
                    "your App.navigation/1."
        end
    end
  end

  defp pop_to_module([], _target), do: :not_found

  defp pop_to_module([{module, socket} | rest], target) do
    if module == target do
      {:found, module, socket, rest}
    else
      pop_to_module(rest, target)
    end
  end

  defp clear_nav_action(socket) do
    Dala.Socket.put_dala(socket, :nav_action, nil)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp decode_notification_json(json) when is_binary(json) do
    case :json.decode(json) do
      map when is_map(map) ->
        source =
          case Map.get(map, "source", "local") do
            "push" -> :push
            _ -> :local
          end

        data =
          case Map.get(map, "data") do
            d when is_map(d) ->
              Map.new(d, fn {k, v} -> {String.to_atom(k), v} end)

            _ ->
              %{}
          end

        %{
          id: Map.get(map, "id"),
          title: Map.get(map, "title"),
          body: Map.get(map, "body"),
          data: data,
          source: source
        }

      _ ->
        %{source: :local, data: %{}}
    end
  end

  # ── Render pipeline ───────────────────────────────────────────────────────

  defp do_render(module, socket, transition \\ :none) do
    platform = socket.__dala__.platform
    list_renderers = Map.get(socket.__dala__, :list_renderers, %{})
    socket = ensure_safe_area(socket, platform)

    # Skip render if nothing changed (except for navigation)
    changed = socket.__dala__.changed
    has_changes = MapSet.size(changed) > 0
    is_navigation = transition != :none

    if has_changes or is_navigation do
      {tree, active_component_keys} =
        module.render(socket.assigns)
        |> Dala.List.expand(list_renderers, self())
        |> Dala.Component.expand(self(), platform)

      # Convert to Dala.Node struct for proper diffing
      new_node = Dala.Node.from_map(tree, "root")

      Dala.ComponentRegistry.reconcile(self(), active_component_keys)

      # Get previous tree from socket metadata
      old_tree = Dala.Socket.get_dala(socket, :last_tree)

      # Use patch-based rendering
      {:ok, _patches} =
        Dala.Renderer.render_patches(old_tree, new_node, platform, Dala.Native, transition)

      # Store the new tree for next diff
      socket = Dala.Socket.put_dala(socket, :last_tree, new_node)
      socket = Dala.Socket.clear_changed(socket)
      Dala.Socket.put_root_view(socket, :rendered)
    else
      # Nothing changed, keep existing UI but still clear the changed set
      # so the next render doesn't incorrectly think something changed
      socket = Dala.Socket.clear_changed(socket)
      socket
    end
  end

  defp ensure_safe_area(socket, platform) do
    if Map.has_key?(socket.assigns, :safe_area) do
      socket
    else
      safe_area =
        if platform == :ios do
          {t, r, b, l} = Dala.Native.safe_area()
          %{top: t, right: r, bottom: b, left: l}
        else
          %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0}
        end

      Dala.Socket.assign(socket, :safe_area, safe_area)
    end
  end
end
