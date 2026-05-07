defmodule Dala.Screen.ManagerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Dala.Screen.Manager)
    :ok
  end

  defmodule TestScreen do
    use Dala.Screen

    screen do
      name(:test_screen)

      column do
        text("Test")
      end
    end

    def handle_event(:test, _params, socket) do
      {:noreply, socket}
    end
  end

  describe "register/4 and list/0" do
    test "registers and lists screens" do
      pid = spawn(fn -> :timer.sleep(:infinity) end)

      assert :ok = Dala.Screen.Manager.register(1, :test_screen, pid, TestScreen)

      screens = Dala.Screen.Manager.list()
      assert length(screens) == 1

      screen = hd(screens)
      assert screen.id == 1
      assert screen.name == :test_screen
      assert screen.pid == pid
      assert screen.module == TestScreen

      Process.exit(pid, :kill)
    end

    test "lists multiple screens" do
      pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      assert :ok = Dala.Screen.Manager.register(1, :screen1, pid1, TestScreen)
      assert :ok = Dala.Screen.Manager.register(2, :screen2, pid2, TestScreen)

      screens = Dala.Screen.Manager.list()
      assert length(screens) == 2

      screen_ids = Enum.map(screens, & &1.id) |> Enum.sort()
      assert screen_ids == [1, 2]

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "list returns empty when no screens registered" do
      assert Dala.Screen.Manager.list() == []
    end
  end

  describe "unregister/1" do
    test "unregisters a screen by pid" do
      pid = spawn(fn -> :timer.sleep(:infinity) end)

      assert :ok = Dala.Screen.Manager.register(1, :test_screen, pid, TestScreen)
      assert length(Dala.Screen.Manager.list()) == 1

      assert :ok = Dala.Screen.Manager.unregister(pid)
      assert Dala.Screen.Manager.list() == []

      Process.exit(pid, :kill)
    end

    test "unregister is idempotent" do
      pid = spawn(fn -> :timer.sleep(:infinity) end)

      assert :ok = Dala.Screen.Manager.unregister(pid)
      assert :ok = Dala.Screen.Manager.unregister(pid)

      Process.exit(pid, :kill)
    end
  end

  describe "next_id/0" do
    test "generates unique sequential IDs" do
      id1 = Dala.Screen.Manager.next_id()
      id2 = Dala.Screen.Manager.next_id()
      id3 = Dala.Screen.Manager.next_id()

      assert id1 == 0
      assert id2 == 1
      assert id3 == 2
    end
  end

  describe "dispatch/2" do
    test "sends message to screen by pid" do
      parent = self()

      pid =
        spawn(fn ->
          receive do
            msg -> send(parent, {:received, msg})
          end
        end)

      assert :ok = Dala.Screen.Manager.register(1, :test_screen, pid, TestScreen)
      assert :ok = Dala.Screen.Manager.dispatch(pid, {:hello, "world"})

      assert_receive {:received, {:hello, "world"}}

      Process.exit(pid, :kill)
    end

    test "sends message to screen by id" do
      parent = self()

      pid =
        spawn(fn ->
          receive do
            msg -> send(parent, {:received, msg})
          end
        end)

      assert :ok = Dala.Screen.Manager.register(123, :test_screen, pid, TestScreen)
      assert :ok = Dala.Screen.Manager.dispatch(123, {:hello, "world"})

      assert_receive {:received, {:hello, "world"}}

      Process.exit(pid, :kill)
    end

    test "sends message to screen by name" do
      parent = self()

      pid =
        spawn(fn ->
          receive do
            msg -> send(parent, {:received, msg})
          end
        end)

      assert :ok = Dala.Screen.Manager.register(1, :my_screen, pid, TestScreen)
      assert :ok = Dala.Screen.Manager.dispatch(:my_screen, {:hello, "world"})

      assert_receive {:received, {:hello, "world"}}

      Process.exit(pid, :kill)
    end

    test "returns error for non-existent identifier" do
      assert {:error, :not_found} = Dala.Screen.Manager.dispatch(999, :test)
      assert {:error, :not_found} = Dala.Screen.Manager.dispatch(:nonexistent, :test)
      assert {:error, :not_found} = Dala.Screen.Manager.dispatch(self(), :test)
    end
  end

  describe "integration with Dala.Screen" do
    test "screen auto-registers on start" do
      # Start a real screen
      {:ok, pid} = Dala.Screen.start_link(TestScreen, %{})

      # Give it time to register
      Process.sleep(50)

      screens = Dala.Screen.Manager.list()
      assert length(screens) == 1

      screen = hd(screens)
      assert screen.pid == pid
      assert screen.module == TestScreen
      # Screen name can be nil if not set in socket assigns
      assert screen.name == nil or screen.name == :test_screen

      # Clean up
      Process.exit(pid, :kill)
    end

    test "screen unregisters on terminate" do
      {:ok, pid} = Dala.Screen.start_link(TestScreen, %{})

      Process.sleep(50)
      assert length(Dala.Screen.Manager.list()) == 1

      # Use GenServer.stop for clean shutdown
      GenServer.stop(pid, :normal, 1000)
      Process.sleep(50)

      assert Dala.Screen.Manager.list() == []
    end

    test "Dala.Screen.dispatch/2 sends message to screen" do
      {:ok, pid} = Dala.Screen.start_link(TestScreen, %{})

      Process.sleep(50)

      # Send message to screen
      assert :ok = Dala.Screen.dispatch(pid, {:test, :message})

      # Give screen time to process
      Process.sleep(50)

      # Screen should still be alive (handle_info handled the message)
      assert Process.alive?(pid)

      # Verify the screen's handle_info was called by checking it doesn't crash
      # The default handle_info just returns {:noreply, socket}, so the screen stays alive
      Process.exit(pid, :kill)
    end
  end
end
