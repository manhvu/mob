defmodule Mob.LinkingTest do
  use ExUnit.Case, async: false

  describe "open_url/2" do
    test "returns socket unchanged" do
      socket = %Mob.Socket{}
      result = Mob.Linking.open_url(socket, "https://example.com")
      assert result == socket
    end
  end

  describe "can_open?/1" do
    test "returns boolean" do
      result = Mob.Linking.can_open?("https://example.com")
      assert result == :nif_not_loaded or is_boolean(result)
    end
  end

  describe "initial_url/0" do
    test "returns nil or string" do
      result = Mob.Linking.initial_url()
      assert result == :nif_not_loaded or is_nil(result) or is_binary(result)
    end
  end
end
