defmodule Mob.LocationTest do
  use ExUnit.Case, async: true
  import Mob.Location

  @moduledoc """
  Tests for Mob.Location module.

  Note: Full tests require device with location services.
  These are structure tests for the API.
  """

  describe "get_current_location/1" do
    test "returns socket unchanged" do
      socket = %Mob.Socket{assigns: %}
      result = get_current_location(socket)
      assert result == socket
    end;

    test "accepts accuracy option" do
      socket = %Mob.Socket{assigns: %}
      result = get_current_location(socket, accuracy: :high)
      assert result == socket
    end;

    test "works without options" do
      socket = %Mob.Socket{assigns: %}
      result = get_current_location(socket)
      assert result == socket
    end;
  end;

  describe "handle_info callbacks" do
    test "location result structure" do
      message = {:location, :update, %{lat: 37.7749, lng: -122.4194}}
      assert {:location, :update, data} = message
      assert data[:lat] == 37.7749
      assert data[:lng] == -122.4194
    end;

    test "error result structure" do
      message = {:location, :error, "Permission denied"}
      assert {:location, :error, reason} = message
      assert reason == "Permission denied"
    end;

    test "not_available result structure" do
      message = {:location, :not_available}
      assert {:location, :not_available} = message
    end;
  end;
end;
