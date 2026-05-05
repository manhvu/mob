defmodule Dala.ComponentTest do
  use ExUnit.Case, async: true

  # Tests cover pure Elixir behaviour — mount, render, handle_event, update.
  # The NIF-calling path (register_component) requires a device and is tested on-device.

  defmodule CounterComponent do
    use Dala.Component

    def mount(props, socket) do
      {:ok, Dala.Socket.assign(socket, :count, props[:initial] || 0)}
    end

    def render(assigns) do
      %{count: assigns.count}
    end

    def handle_event("increment", _payload, socket) do
      {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
    end
  end

  defmodule StatelessComponent do
    use Dala.Component

    def render(assigns) do
      %{label: assigns[:label] || ""}
    end
  end

  # ── Dala.Component behaviour defaults ──────────────────────────────────────

  describe "use Dala.Component" do
    test "mount/2 default returns {:ok, socket} unchanged" do
      socket = Dala.Socket.new(StatelessComponent, platform: :no_render)
      assert {:ok, ^socket} = StatelessComponent.mount(%{}, socket)
    end

    test "update/2 default delegates to mount/2" do
      socket = Dala.Socket.new(CounterComponent, platform: :no_render)
      {:ok, mounted} = CounterComponent.mount(%{initial: 5}, socket)
      {:ok, updated} = CounterComponent.update(%{initial: 10}, mounted)
      assert updated.assigns.count == 10
    end

    test "terminate/2 default returns :ok" do
      socket = Dala.Socket.new(StatelessComponent, platform: :no_render)
      assert :ok = StatelessComponent.terminate(:normal, socket)
    end

    test "handle_event/3 default raises for unhandled events" do
      socket = Dala.Socket.new(StatelessComponent, platform: :no_render)

      assert_raise RuntimeError, ~r/unhandled component event/, fn ->
        StatelessComponent.handle_event("unknown", %{}, socket)
      end
    end
  end

  # ── CounterComponent callbacks ─────────────────────────────────────────────

  describe "CounterComponent" do
    test "mount/2 assigns initial count from props" do
      socket = Dala.Socket.new(CounterComponent, platform: :no_render)
      {:ok, mounted} = CounterComponent.mount(%{initial: 7}, socket)
      assert mounted.assigns.count == 7
    end

    test "mount/2 defaults count to 0 when :initial absent" do
      socket = Dala.Socket.new(CounterComponent, platform: :no_render)
      {:ok, mounted} = CounterComponent.mount(%{}, socket)
      assert mounted.assigns.count == 0
    end

    test "render/1 returns props map with count" do
      socket = Dala.Socket.new(CounterComponent, platform: :no_render)
      {:ok, mounted} = CounterComponent.mount(%{initial: 3}, socket)
      assert CounterComponent.render(mounted.assigns) == %{count: 3}
    end

    test "handle_event increment increments count" do
      socket = Dala.Socket.new(CounterComponent, platform: :no_render)
      {:ok, mounted} = CounterComponent.mount(%{initial: 0}, socket)
      {:noreply, updated} = CounterComponent.handle_event("increment", %{}, mounted)
      assert updated.assigns.count == 1
    end
  end

  # ── Dala.UI.native_view ────────────────────────────────────────────────────

  describe "Dala.UI.native_view/2" do
    test "returns a :native_view node" do
      node = Dala.UI.native_view(CounterComponent, id: :counter)
      assert node.type == :native_view
    end

    test "includes the module in props" do
      node = Dala.UI.native_view(CounterComponent, id: :counter)
      assert node.props.module == CounterComponent
    end

    test "includes the id in props" do
      node = Dala.UI.native_view(CounterComponent, id: :counter)
      assert node.props.id == :counter
    end

    test "includes extra props" do
      node = Dala.UI.native_view(CounterComponent, id: :counter, initial: 5)
      assert node.props.initial == 5
    end

    test "children is always empty" do
      assert Dala.UI.native_view(CounterComponent, id: :counter).children == []
    end

    test "accepts a map" do
      node = Dala.UI.native_view(CounterComponent, %{id: :counter})
      assert node.props.id == :counter
    end
  end

  # ── Dala.ComponentRegistry ─────────────────────────────────────────────────

  describe "Dala.ComponentRegistry" do
    setup do
      # Start a temporary registry for each test to avoid global state
      {:ok, reg} = start_supervised({Dala.ComponentRegistry, []})
      # Override the global name for this test via process dict workaround is complex;
      # instead test via the ETS table directly after start.
      # The registry GenServer creates the named ETS table — we use it directly.
      {:ok, reg: reg}
    end

    test "register and lookup succeed" do
      screen = self()
      Dala.ComponentRegistry.register(screen, :my_chart, CounterComponent, self())
      assert {:ok, _pid} = Dala.ComponentRegistry.lookup(screen, :my_chart, CounterComponent)
    end

    test "lookup returns :not_found for unknown key" do
      assert {:error, :not_found} =
               Dala.ComponentRegistry.lookup(self(), :missing, CounterComponent)
    end

    test "deregister removes the entry" do
      screen = self()
      Dala.ComponentRegistry.register(screen, :temp, CounterComponent, self())
      Dala.ComponentRegistry.deregister(screen, :temp, CounterComponent)

      assert {:error, :not_found} =
               Dala.ComponentRegistry.lookup(screen, :temp, CounterComponent)
    end

    test "duplicate id raises" do
      screen = self()
      Dala.ComponentRegistry.register(screen, :dupe, CounterComponent, self())

      assert_raise ArgumentError, ~r/duplicate id/, fn ->
        Dala.ComponentRegistry.register(screen, :dupe, CounterComponent, spawn(fn -> nil end))
      end
    end
  end
end
