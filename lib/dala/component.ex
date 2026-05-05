defmodule Dala.Component do
  @moduledoc """
  Behaviour for native view components.

  A component is a stateful Elixir process paired with a platform-native view
  registered by name on iOS/Android. The BEAM owns the state; the native side
  owns the rendering.

  ## Lifecycle

  1. The parent screen declares `Dala.UI.native_view(MyComponent, id: :my_id, ...)`
  2. On first render, a `Dala.ComponentServer` process is started and `mount/2` is called
  3. `render/1` is called to get the props map forwarded to the native factory
  4. On subsequent renders, `update/2` is called with new props from the parent
  5. When the native view fires an event, `handle_event/3` is called
  6. After any state change, `render/1` is re-called and native props are updated
  7. When the component leaves the tree, the process is stopped and `terminate/2` is called

  ## Usage

      defmodule MyApp.ChartComponent do
        use Dala.Component

        def mount(props, socket) do
          {:ok, Dala.Socket.assign(socket, :data, props[:data])}
        end

        def render(assigns) do
          %{data: assigns.data}
        end

        def handle_event("segment_tapped", %{"index" => i}, socket) do
          {:noreply, Dala.Socket.assign(socket, :selected, i)}
        end
      end

  ## Native registration

  Register the view factory at app startup:

      # iOS (Swift) — strip "Elixir." prefix and replace "." with "_":
      dalaNativeViewRegistry.shared.register("MyApp_ChartComponent") { props, send in
          AnyView(ChartView(data: props["data"]) { index in
              send("segment_tapped", ["index": index])
          })
      }

      # Android (Kotlin):
      dalaNativeViewRegistry.register("MyApp_ChartComponent") { props, send ->
          ChartView(data = props["data"]) { index ->
              send("segment_tapped", mapOf("index" to index))
          }
      }

  ## Declaration

      Dala.UI.native_view(MyApp.ChartComponent, id: :revenue_chart, data: @points)

  The `:id` must be unique per screen. Duplicate ids on the same screen raise at render time.

  ## Stateless components

  If a component has no internal state, omit `mount/2` and `handle_info/2`. The
  default `handle_event/3` raises for any event — add clauses for the events your
  native view fires, or delegate to the parent screen by forwarding via `send/2`.
  """

  @callback mount(props :: map(), socket :: Dala.Socket.t()) ::
              {:ok, Dala.Socket.t()} | {:error, term()}

  @callback update(props :: map(), socket :: Dala.Socket.t()) ::
              {:ok, Dala.Socket.t()}

  @callback render(assigns :: map()) :: map()

  @callback handle_event(event :: String.t(), payload :: map(), socket :: Dala.Socket.t()) ::
              {:noreply, Dala.Socket.t()}

  @callback handle_info(message :: term(), socket :: Dala.Socket.t()) ::
              {:noreply, Dala.Socket.t()}

  @callback terminate(reason :: term(), socket :: Dala.Socket.t()) :: term()

  @optional_callbacks [update: 2, handle_event: 3, handle_info: 2, terminate: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Dala.Component

      def mount(props, socket), do: {:ok, socket}

      def update(props, socket), do: mount(props, socket)

      def handle_event(event, _payload, _socket) do
        raise RuntimeError,
              "unhandled component event #{inspect(event)} in #{inspect(__MODULE__)}. " <>
                "Add a handle_event/3 clause to handle it."
      end

      def handle_info(_message, socket), do: {:noreply, socket}
      def terminate(_reason, _socket), do: :ok

      defoverridable mount: 2, update: 2, handle_event: 3, handle_info: 2, terminate: 2
    end
  end

  # ── Tree expansion ────────────────────────────────────────────────────────

  @doc """
  Walk a node tree, expanding `:native_view` nodes into serialisable form.

  Starts or updates component processes, collects their rendered props, and
  injects the NIF handle. Returns `{expanded_tree, active_keys}` where
  `active_keys` is a `MapSet` of `{id, module}` pairs seen in this render —
  used by the screen to stop components that have left the tree.
  """
  @spec expand(map(), pid(), atom()) :: {map(), MapSet.t()}
  def expand(tree, screen_pid, platform) do
    active = MapSet.new()
    walk(tree, screen_pid, platform, active)
  end

  defp walk(%{type: :native_view, props: props} = node, screen_pid, platform, active) do
    module = props[:module]
    id = props[:id]

    unless is_atom(module) and is_atom(id) do
      raise ArgumentError,
            "Dala.UI.native_view requires :module and :id as atoms, got: #{inspect(props)}"
    end

    component_pid = ensure_started(screen_pid, id, module, props, platform)
    rendered_props = Dala.ComponentServer.render_props(component_pid)
    handle = Dala.ComponentServer.get_handle(component_pid)

    enriched =
      Map.merge(rendered_props, %{
        module: module_name(module),
        id: Atom.to_string(id),
        component_handle: handle
      })

    active = MapSet.put(active, {id, module})
    {%{node | props: enriched}, active}
  end

  defp walk(%{children: children} = node, screen_pid, platform, active) do
    {new_children, active} =
      Enum.map_reduce(children, active, fn child, acc ->
        walk(child, screen_pid, platform, acc)
      end)

    {%{node | children: new_children}, active}
  end

  defp walk(node, _screen_pid, _platform, active), do: {node, active}

  defp ensure_started(screen_pid, id, module, props, platform) do
    case Dala.ComponentRegistry.lookup(screen_pid, id, module) do
      {:ok, pid} ->
        Dala.ComponentServer.update(pid, props)
        pid

      {:error, :not_found} ->
        {:ok, pid} =
          Dala.ComponentServer.start(
            module: module,
            id: id,
            screen_pid: screen_pid,
            props: props,
            platform: platform
          )

        pid
    end
  end

  # "Elixir.MyApp.ChartComponent" → "MyApp_ChartComponent"
  defp module_name(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
    |> String.replace(".", "_")
  end
end
