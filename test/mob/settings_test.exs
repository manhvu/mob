defmodule Mob.SettingsTest do
  use ExUnit.Case, async: false

  describe "get/1" do
    test "returns nil for missing key" do
      result = Mob.Settings.get("nonexistent_key")
      assert result == nil
    end
  end

  describe "set/3" do
    test "returns socket unchanged" do
      socket = %Mob.Socket{}
      result = Mob.Settings.set(socket, "theme", "dark")
      assert result == socket
    end
  end

  describe "watch/2" do
    test "returns socket unchanged" do
      socket = %Mob.Socket{}
      result = Mob.Settings.watch(socket, "theme")
      assert result == socket
    end
  end
end
