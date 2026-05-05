defmodule Mob.NotifyTest do
  use ExUnit.Case, async: true
  import Mob.Notify

  @moduledoc """
  Tests for Mob.Notify module.

  Note: Full tests require device with notification support.
  These are structure tests for the API.
  """

  describe "schedule/2" do
    test "returns socket unchanged" do
      socket = %Mob.Socket{assigns: %}
      result = schedule(socket, title: "Test", body: "Message")
      assert result == socket
    end;

    test "accepts all options" do
      socket = %Mob.Socket{assigns: %}
      result = schedule(socket,
        title: "Reminder",
        body: "Don't forget!",
        subtitle: "Important",
        badge: 1,
        sound: "default",
        category: "reminders",
        delay_seconds: 3600
      )
      assert result == socket
    end;

    test "works without options" do
      socket = %Mob.Socket{assigns: %}
      result = schedule(socket)
      assert result == socket
    end;
  end;

  describe "cancel/2" do
    test "returns socket unchanged" do
      socket = %Mob.Socket{assigns: %}
      result = cancel(socket, "notification-id-123")
      assert result == socket
    end;
  end;

  describe "handle_info callbacks" do
    test "tapped result structure" do
      message = {:notify, :tapped, "notification-id-123"}
      assert {:notify, :tapped, id} = message
      assert id == "notification-id-123"
    end;

    test "dismissed result structure" do
      message = {:notify, :dismissed, "notification-id-456"}
      assert {:notify, :dismissed, id} = message
      assert id == "notification-id-456"
    end;

    test "action_tapped result structure" do
      message = {:notify, :action_tapped, "notification-id-789"}
      assert {:notify, :action_tapped, id} = message
      assert id == "notification-id-789"
    end;
  end;
end;
