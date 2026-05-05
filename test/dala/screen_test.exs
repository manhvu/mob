defmodule Dala.ScreenTest do
  use ExUnit.Case, async: true

  # A minimal screen that uses the behaviour
  defmodule CounterScreen do
    use Dala.Screen

    def mount(_params, _session, socket) do
      {:ok, Dala.Socket.assign(socket, :count, 0)}
    end

    def render(assigns) do
      %{
        type: :column,
        props: %{},
        children: [
          %{type: :text, props: %{text: "Count: #{assigns.count}"}, children: []}
        ]
      }
    end

    def handle_event("increment", _params, socket) do
      {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
    end

    def handle_event("decrement", _params, socket) do
      {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count - 1)}
    end
  end

  # A screen that relies entirely on default implementations
  defmodule MinimalScreen do
    use Dala.Screen

    def mount(_params, _session, socket), do: {:ok, socket}
    def render(_assigns), do: %{type: :column, props: %{}, children: []}
  end

  describe "use Dala.Screen" do
    test "injects default handle_info that noops" do
      socket = Dala.Socket.new(MinimalScreen)
      assert {:noreply, ^socket} = MinimalScreen.handle_info(:some_message, socket)
    end

    test "injects default terminate that returns :ok" do
      socket = Dala.Socket.new(MinimalScreen)
      assert :ok = MinimalScreen.terminate(:normal, socket)
    end

    test "injects default handle_event that raises" do
      socket = Dala.Socket.new(MinimalScreen)

      assert_raise RuntimeError, ~r/unhandled event/, fn ->
        MinimalScreen.handle_event("unknown", %{}, socket)
      end
    end
  end

  describe "mount/3" do
    test "returns :ok tuple with initialized socket" do
      socket = Dala.Socket.new(CounterScreen)
      assert {:ok, mounted} = CounterScreen.mount(%{}, %{}, socket)
      assert mounted.assigns.count == 0
    end
  end

  describe "render/1" do
    test "returns a component tree map" do
      socket = Dala.Socket.new(CounterScreen) |> Dala.Socket.assign(:count, 3)
      tree = CounterScreen.render(socket.assigns)
      assert %{type: :column, children: [%{type: :text, props: %{text: "Count: 3"}}]} = tree
    end
  end

  describe "handle_event/3" do
    test "increment increases count" do
      socket = Dala.Socket.new(CounterScreen) |> Dala.Socket.assign(:count, 0)
      {:noreply, updated} = CounterScreen.handle_event("increment", %{}, socket)
      assert updated.assigns.count == 1
    end

    test "decrement decreases count" do
      socket = Dala.Socket.new(CounterScreen) |> Dala.Socket.assign(:count, 5)
      {:noreply, updated} = CounterScreen.handle_event("decrement", %{}, socket)
      assert updated.assigns.count == 4
    end

    test "unknown event raises FunctionClauseError when screen has partial handle_event" do
      socket = Dala.Socket.new(CounterScreen)

      assert_raise FunctionClauseError, fn ->
        CounterScreen.handle_event("unknown", %{}, socket)
      end
    end

    test "unknown event raises RuntimeError when screen has no handle_event at all" do
      socket = Dala.Socket.new(MinimalScreen)

      assert_raise RuntimeError, ~r/unhandled event/, fn ->
        MinimalScreen.handle_event("unknown", %{}, socket)
      end
    end
  end

  describe "screen process" do
    test "start_link/2 starts a GenServer and returns {:ok, pid}" do
      assert {:ok, pid} = Dala.Screen.start_link(CounterScreen, %{})
      assert is_pid(pid)
      GenServer.stop(pid)
    end

    test "started screen has mounted assigns" do
      {:ok, pid} = Dala.Screen.start_link(CounterScreen, %{})
      socket = Dala.Screen.get_socket(pid)
      assert socket.assigns.count == 0
      GenServer.stop(pid)
    end

    test "dispatch/3 sends event and updates state" do
      {:ok, pid} = Dala.Screen.start_link(CounterScreen, %{})
      :ok = Dala.Screen.dispatch(pid, "increment", %{})
      socket = Dala.Screen.get_socket(pid)
      assert socket.assigns.count == 1
      GenServer.stop(pid)
    end

    test "multiple dispatches accumulate" do
      {:ok, pid} = Dala.Screen.start_link(CounterScreen, %{})
      :ok = Dala.Screen.dispatch(pid, "increment", %{})
      :ok = Dala.Screen.dispatch(pid, "increment", %{})
      :ok = Dala.Screen.dispatch(pid, "increment", %{})
      :ok = Dala.Screen.dispatch(pid, "decrement", %{})
      socket = Dala.Screen.get_socket(pid)
      assert socket.assigns.count == 2
      GenServer.stop(pid)
    end

    test "render skipped when nothing changed" do
      {:ok, pid} = Dala.Screen.start_link(CounterScreen, %{})
      socket = Dala.Screen.get_socket(pid)
      # Clear the changed set (simulate a render just happened)
      socket = Dala.Socket.clear_changed(socket)
      # Now send a message that doesn't change assigns
      send(pid, {:fake_message, :no_change})
      # Give it a moment to process
      :timer.sleep(50)
      # Verify changed? returns false for :count
      refute Dala.Socket.changed?(socket, :count)
      GenServer.stop(pid)
    end
  end
end
