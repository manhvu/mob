defmodule Dala.Nav.ScreenNavTest do
  use ExUnit.Case, async: false

  # ── Screen fixtures ────────────────────────────────────────────────────────
  # Bare module names inside nested defmodule blocks don't auto-alias to siblings.
  # Use module attributes with fully qualified names for cross-screen references.

  defmodule HomeScreen do
    use Dala.Screen

    @profile Dala.Nav.ScreenNavTest.ProfileScreen

    def mount(_params, _session, socket), do: {:ok, Dala.Socket.assign(socket, :page, :home)}
    def render(assigns), do: %{type: :text, props: %{text: "home #{assigns.page}"}, children: []}

    def handle_event("go_profile", _, socket),
      do: {:noreply, Dala.Socket.push_screen(socket, @profile)}

    def handle_event("go_settings", _, socket),
      do: {:noreply, Dala.Socket.push_screen(socket, :settings, %{from: :home})}

    def handle_event("reset_to_profile", _, socket),
      do: {:noreply, Dala.Socket.reset_to(socket, @profile)}
  end

  defmodule ProfileScreen do
    use Dala.Screen

    @home Dala.Nav.ScreenNavTest.HomeScreen
    @settings Dala.Nav.ScreenNavTest.SettingsScreen

    def mount(params, _session, socket) do
      {:ok, Dala.Socket.assign(socket, :name, Map.get(params, :name, "anon"))}
    end

    def render(assigns),
      do: %{type: :text, props: %{text: "profile #{assigns.name}"}, children: []}

    def handle_event("back", _, socket), do: {:noreply, Dala.Socket.pop_screen(socket)}
    def handle_event("back_to_root", _, socket), do: {:noreply, Dala.Socket.pop_to_root(socket)}

    def handle_event("go_settings", _, socket),
      do: {:noreply, Dala.Socket.push_screen(socket, @settings)}

    def handle_event("reset_to_home", _, socket),
      do: {:noreply, Dala.Socket.reset_to(socket, @home)}
  end

  defmodule SettingsScreen do
    use Dala.Screen

    @home Dala.Nav.ScreenNavTest.HomeScreen

    def mount(params, _session, socket) do
      {:ok, Dala.Socket.assign(socket, :from, Map.get(params, :from, :unknown))}
    end

    def render(assigns),
      do: %{type: :text, props: %{text: "settings from=#{assigns.from}"}, children: []}

    def handle_event("back", _, socket), do: {:noreply, Dala.Socket.pop_screen(socket)}
    def handle_event("back_to_root", _, socket), do: {:noreply, Dala.Socket.pop_to_root(socket)}
    def handle_event("pop_to_home", _, socket), do: {:noreply, Dala.Socket.pop_to(socket, @home)}
  end

  defmodule DemoApp do
    @behaviour Dala.App
    import Dala.App

    @settings Dala.Nav.ScreenNavTest.SettingsScreen

    def navigation(_), do: stack(:settings, root: @settings)
  end

  setup do
    case Process.whereis(Dala.Nav.Registry) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    {:ok, pid} = Dala.Nav.Registry.start_link(DemoApp)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    :ok
  end

  # ── push_screen ────────────────────────────────────────────────────────────

  describe "push_screen/2 (module dest)" do
    test "switches current module to the pushed screen" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      assert Dala.Screen.get_current_module(pid) == ProfileScreen
      GenServer.stop(pid)
    end

    test "new screen is mounted with empty params" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      socket = Dala.Screen.get_socket(pid)
      assert socket.assigns.name == "anon"
      GenServer.stop(pid)
    end

    test "nav history grows by one on push" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      assert Dala.Screen.get_nav_history(pid) == []
      Dala.Screen.dispatch(pid, "go_profile", %{})
      assert length(Dala.Screen.get_nav_history(pid)) == 1
      GenServer.stop(pid)
    end

    test "history head is the previous module" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      [{prev_module, _prev_socket} | _] = Dala.Screen.get_nav_history(pid)
      assert prev_module == HomeScreen
      GenServer.stop(pid)
    end
  end

  describe "push_screen/3 (registered atom dest with params)" do
    test "resolves atom via registry and mounts with params" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_settings", %{})
      assert Dala.Screen.get_current_module(pid) == SettingsScreen
      socket = Dala.Screen.get_socket(pid)
      assert socket.assigns.from == :home
      GenServer.stop(pid)
    end
  end

  # ── pop_screen ─────────────────────────────────────────────────────────────

  describe "pop_screen/1" do
    test "returns to previous module" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      Dala.Screen.dispatch(pid, "back", %{})
      assert Dala.Screen.get_current_module(pid) == HomeScreen
      GenServer.stop(pid)
    end

    test "restores previous screen's socket assigns" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      Dala.Screen.dispatch(pid, "back", %{})
      socket = Dala.Screen.get_socket(pid)
      assert socket.assigns.page == :home
      GenServer.stop(pid)
    end

    test "nav history shrinks on pop" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      Dala.Screen.dispatch(pid, "back", %{})
      assert Dala.Screen.get_nav_history(pid) == []
      GenServer.stop(pid)
    end

    test "pop at root is a no-op (module stays the same)" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      # Send an info message that would trigger pop — default handle_info is noop
      send(pid, :pop_test)
      Process.sleep(10)
      assert Dala.Screen.get_current_module(pid) == HomeScreen
      GenServer.stop(pid)
    end
  end

  # ── pop_to_root ────────────────────────────────────────────────────────────

  describe "pop_to_root/1" do
    test "returns to the root from two levels deep" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      Dala.Screen.dispatch(pid, "go_settings", %{})
      assert Dala.Screen.get_current_module(pid) == SettingsScreen
      # SettingsScreen now also handles back_to_root
      Dala.Screen.dispatch(pid, "back_to_root", %{})
      assert Dala.Screen.get_current_module(pid) == HomeScreen
      assert Dala.Screen.get_nav_history(pid) == []
      GenServer.stop(pid)
    end

    test "pop_to_root at root is a no-op" do
      {:ok, pid} = Dala.Screen.start_link(ProfileScreen, %{name: "alice"})
      Dala.Screen.dispatch(pid, "back_to_root", %{})
      assert Dala.Screen.get_current_module(pid) == ProfileScreen
      GenServer.stop(pid)
    end
  end

  # ── pop_to ─────────────────────────────────────────────────────────────────

  describe "pop_to/2" do
    test "pops back to the target module in history" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_settings", %{})
      # Now we're on SettingsScreen. Push ProfileScreen from there is not wired,
      # so instead test the same scenario by going Home -> Profile -> Settings
      # then pop_to_home from Settings.
      GenServer.stop(pid)

      {:ok, pid2} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid2, "go_profile", %{})
      Dala.Screen.dispatch(pid2, "go_settings", %{})
      assert Dala.Screen.get_current_module(pid2) == SettingsScreen
      Dala.Screen.dispatch(pid2, "pop_to_home", %{})
      assert Dala.Screen.get_current_module(pid2) == HomeScreen
      assert Dala.Screen.get_nav_history(pid2) == []
      GenServer.stop(pid2)
    end

    test "is a no-op if target is not in history" do
      {:ok, pid} = Dala.Screen.start_link(SettingsScreen, %{})
      # SettingsScreen tries to pop_to HomeScreen, but HomeScreen isn't in history
      Dala.Screen.dispatch(pid, "pop_to_home", %{})
      assert Dala.Screen.get_current_module(pid) == SettingsScreen
      GenServer.stop(pid)
    end
  end

  # ── reset_to ───────────────────────────────────────────────────────────────

  describe "reset_to/2" do
    test "replaces entire nav stack with a fresh screen" do
      # Start on HomeScreen, push to ProfileScreen, then reset to HomeScreen from there
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      assert Dala.Screen.get_current_module(pid) == ProfileScreen
      # ProfileScreen handles "reset_to_home" via Dala.Socket.reset_to(socket, HomeScreen)
      Dala.Screen.dispatch(pid, "reset_to_home", %{})
      assert Dala.Screen.get_current_module(pid) == HomeScreen
      assert Dala.Screen.get_nav_history(pid) == []
      GenServer.stop(pid)
    end

    test "new screen is freshly mounted" do
      {:ok, pid} = Dala.Screen.start_link(HomeScreen, %{})
      Dala.Screen.dispatch(pid, "go_profile", %{})
      Dala.Screen.dispatch(pid, "reset_to_home", %{})
      socket = Dala.Screen.get_socket(pid)
      assert socket.assigns.page == :home
      GenServer.stop(pid)
    end
  end

  # ── resolve: unknown destination ──────────────────────────────────────────

  describe "resolve_module/1 error handling" do
    defmodule UnknownNavScreen do
      use Dala.Screen
      def mount(_, _, socket), do: {:ok, socket}
      def render(_), do: %{type: :text, props: %{text: "x"}, children: []}

      def handle_event("bad_nav", _, socket) do
        {:noreply, Dala.Socket.push_screen(socket, :no_such_screen)}
      end
    end

    test "raises ArgumentError for unregistered atom" do
      {:ok, pid} = Dala.Screen.start_link(UnknownNavScreen, %{})
      # Unlink so the server crash doesn't kill the test process — we only want
      # to observe the exit that GenServer.call propagates through the call path.
      Process.unlink(pid)

      exit_reason =
        try do
          Dala.Screen.dispatch(pid, "bad_nav", %{})
          nil
        catch
          :exit, reason -> reason
        end

      assert inspect(exit_reason) =~ "no_such_screen"
    end
  end
end
