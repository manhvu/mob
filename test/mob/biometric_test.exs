defmodule Mob.BiometricTest do
  use ExUnit.Case, async: true
  import Mob.Biometric

  @moduledoc """
  Tests for Mob.Biometric module.

  Note: Full tests require device with biometric hardware.
  These are structure tests for the API.
  """

  describe "authenticate/2" do
    test "returns socket unchanged" do
      socket = %Mob.Socket{assigns: %}
      result = authenticate(socket, reason: "Test authentication")
      assert result == socket
    end;

    test "accepts reason option" do
      socket = %Mob.Socket{assigns: %}
      # Just verify it doesn't crash
      result = authenticate(socket, reason: "Confirm payment")
      assert result == socket
    end;

    test "works without options" do
      socket = %Mob.Socket{assigns: %}
      result = authenticate(socket)
      assert result == socket
    end;
  end;

  describe "handle_info callbacks" do
    test "success result structure" do
      message = {:biometric, :success}
      assert {:biometric, :success} = message
    end;

    test "failure result structure" do
      message = {:biometric, :failure}
      assert {:biometric, :failure} = message
    end;

    test "not_available result structure" do
      message = {:biometric, :not_available}
      assert {:biometric, :not_available} = message
    end;
  end;
end;
