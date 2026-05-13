defmodule Dala.SocketTest do
  use ExUnit.Case, async: true

  alias Dala.Socket

  describe "new/1" do
    test "creates socket with empty assigns" do
      socket = Socket.new(MyScreen)
      assert socket.assigns == %{}
    end

    test "stores the screen module" do
      socket = Socket.new(MyScreen)
      assert socket.__dala__.screen == MyScreen
    end

    test "defaults platform to :android" do
      socket = Socket.new(MyScreen)
      assert socket.__dala__.platform == :android
    end

    test "accepts platform option" do
      socket = Socket.new(MyScreen, platform: :ios)
      assert socket.__dala__.platform == :ios
    end
  end

  describe "assign/3 — single key/value" do
    test "adds a new assign" do
      socket = Socket.new(MyScreen) |> Socket.assign(:count, 0)
      assert socket.assigns.count == 0
    end

    test "overwrites existing assign" do
      socket = Socket.new(MyScreen) |> Socket.assign(:count, 0) |> Socket.assign(:count, 5)
      assert socket.assigns.count == 5
    end

    test "preserves other assigns" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:a, 1)
        |> Socket.assign(:b, 2)
        |> Socket.assign(:a, 99)

      assert socket.assigns.b == 2
      assert socket.assigns.a == 99
    end
  end

  describe "assign/2 — keyword list" do
    test "sets multiple assigns at once" do
      socket = Socket.new(MyScreen) |> Socket.assign(count: 0, name: "test")
      assert socket.assigns.count == 0
      assert socket.assigns.name == "test"
    end

    test "merges with existing assigns" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:existing, true)
        |> Socket.assign(count: 1, name: "hi")

      assert socket.assigns.existing == true
      assert socket.assigns.count == 1
    end

    test "accepts a plain map" do
      socket = Socket.new(MyScreen) |> Socket.assign(%{x: 10, y: 20})
      assert socket.assigns.x == 10
      assert socket.assigns.y == 20
    end
  end

  describe "assign/2 — does not mutate __dala__" do
    test "assign updates changed set" do
      socket = Socket.new(MyScreen)
      socket = Socket.assign(socket, :foo, :bar)
      # __dala__ should now have :foo in changed set
      assert Socket.changed?(socket, :foo)
    end

    test "assign tracks multiple changes" do
      socket = Socket.new(MyScreen)
      socket = Socket.assign(socket, count: 1, name: "test")
      assert Socket.changed?(socket, [:count, :name])
    end
  end

  describe "put_root_view/2" do
    test "stores the root view ref" do
      socket = Socket.new(MyScreen) |> Socket.put_root_view(:some_ref)
      assert socket.__dala__.root_view == :some_ref
    end
  end

  describe "get/2 and get/3" do
    test "get/2 returns value for existing key" do
      socket = Socket.new(MyScreen) |> Socket.assign(:count, 42)
      assert Socket.get(socket, :count) == 42
    end

    test "get/2 returns nil for missing key" do
      socket = Socket.new(MyScreen)
      assert Socket.get(socket, :missing) == nil
    end

    test "get/3 returns default for missing key" do
      socket = Socket.new(MyScreen)
      assert Socket.get(socket, :missing, "default") == "default"
    end

    test "get/3 returns value for existing key, ignoring default" do
      socket = Socket.new(MyScreen) |> Socket.assign(:count, 42)
      assert Socket.get(socket, :count, 0) == 42
    end
  end

  describe "get_dala/2 and get_dala/3" do
    test "get_dala/2 reads internal metadata" do
      socket = Socket.new(MyScreen)
      assert Socket.get_dala(socket, :screen) == MyScreen
      assert Socket.get_dala(socket, :platform) == :android
      assert Socket.get_dala(socket, :nav_stack) == []
    end

    test "get_dala/2 returns nil for unknown key" do
      socket = Socket.new(MyScreen)
      assert Socket.get_dala(socket, :nonexistent) == nil
    end

    test "get_dala/3 returns default for unknown key" do
      socket = Socket.new(MyScreen)
      assert Socket.get_dala(socket, :nonexistent, :fallback) == :fallback
    end
  end

  describe "put_dala/3" do
    test "writes internal metadata" do
      socket = Socket.new(MyScreen) |> Socket.put_dala(:root_view, :my_view)
      assert socket.__dala__.root_view == :my_view
    end

    test "overwrites existing metadata" do
      socket =
        Socket.new(MyScreen)
        |> Socket.put_dala(:root_view, :first)
        |> Socket.put_dala(:root_view, :second)

      assert socket.__dala__.root_view == :second
    end

    test "does not affect assigns" do
      socket = Socket.new(MyScreen) |> Socket.put_dala(:root_view, :view)
      assert socket.assigns == %{}
    end
  end

  describe "navigation helpers" do
    test "push_screen/2 sets nav_action" do
      socket = Socket.new(MyScreen) |> Socket.push_screen(OtherScreen)
      assert socket.__dala__.nav_action == {:push, OtherScreen, %{}}
    end

    test "push_screen/3 sets nav_action with params" do
      socket = Socket.new(MyScreen) |> Socket.push_screen(OtherScreen, %{id: 1})
      assert socket.__dala__.nav_action == {:push, OtherScreen, %{id: 1}}
    end

    test "pop_screen/1 sets nav_action" do
      socket = Socket.new(MyScreen) |> Socket.pop_screen()
      assert socket.__dala__.nav_action == {:pop}
    end

    test "pop_to/2 sets nav_action" do
      socket = Socket.new(MyScreen) |> Socket.pop_to(TargetScreen)
      assert socket.__dala__.nav_action == {:pop_to, TargetScreen}
    end

    test "pop_to_root/1 sets nav_action" do
      socket = Socket.new(MyScreen) |> Socket.pop_to_root()
      assert socket.__dala__.nav_action == {:pop_to_root}
    end

    test "reset_to/2 sets nav_action" do
      socket = Socket.new(MyScreen) |> Socket.reset_to(NewScreen)
      assert socket.__dala__.nav_action == {:reset, NewScreen, %{}}
    end

    test "reset_to/3 sets nav_action with params" do
      socket = Socket.new(MyScreen) |> Socket.reset_to(NewScreen, %{fresh: true})
      assert socket.__dala__.nav_action == {:reset, NewScreen, %{fresh: true}}
    end

    test "navigation does not affect assigns" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:count, 1)
        |> Socket.push_screen(OtherScreen)

      assert socket.assigns.count == 1
    end
  end

  describe "changed?/1 and changed?/2 edge cases" do
    test "changed? returns false for unassigned key" do
      socket = Socket.new(MyScreen)
      refute Socket.changed?(socket, :never_set)
    end

    test "changed? returns false after clear_changed" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:count, 1)
        |> Socket.clear_changed()

      refute Socket.changed?(socket, :count)
    end

    test "changed? with list returns true only if all changed" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:a, 1)
        |> Socket.assign(:b, 2)

      assert Socket.changed?(socket, [:a, :b])
    end

    test "changed? with list returns false if one not changed" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:a, 1)

      refute Socket.changed?(socket, [:a, :b])
    end

    test "changed? with empty list returns true" do
      socket = Socket.new(MyScreen)
      assert Socket.changed?(socket, [])
    end
  end

  describe "clear_changed/1" do
    test "resets the changed set" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:count, 1)
        |> Socket.clear_changed()

      assert socket.__dala__.changed == MapSet.new()
    end

    test "does not affect assigns" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:count, 5)
        |> Socket.clear_changed()

      assert socket.assigns.count == 5
    end
  end

  describe "assign regression — changed tracking across multiple operations" do
    test "assign then clear then assign tracks only new changes" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:a, 1)
        |> Socket.clear_changed()
        |> Socket.assign(:b, 2)

      refute Socket.changed?(socket, :a)
      assert Socket.changed?(socket, :b)
    end

    test "assigning same value still marks as changed" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(:count, 5)
        |> Socket.clear_changed()
        |> Socket.assign(:count, 5)

      assert Socket.changed?(socket, :count)
    end

    test "keyword assign tracks all keys" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(a: 1, b: 2, c: 3)

      assert Socket.changed?(socket, [:a, :b, :c])
    end

    test "map assign tracks all keys" do
      socket =
        Socket.new(MyScreen)
        |> Socket.assign(%{x: 10, y: 20})

      assert Socket.changed?(socket, [:x, :y])
    end
  end
end
