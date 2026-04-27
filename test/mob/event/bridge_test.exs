defmodule Mob.Event.BridgeTest do
  use ExUnit.Case, async: true
  doctest Mob.Event.Bridge

  alias Mob.Event.{Address, Bridge}

  describe "legacy_to_canonical/3 — :tap" do
    test "atom tag produces a button event" do
      assert {:ok, {:mob_event, addr, :tap, nil}} =
               Bridge.legacy_to_canonical({:tap, :save}, MyScreen)

      assert addr.screen == MyScreen
      assert addr.widget == :button
      assert addr.id == :save
      assert addr.instance == nil
    end

    test "binary tag works (data-derived id)" do
      assert {:ok, {:mob_event, addr, :tap, nil}} =
               Bridge.legacy_to_canonical({:tap, "contact:42"}, MyScreen)

      assert addr.id == "contact:42"
    end

    test "tuple tag works (compound id)" do
      assert {:ok, {:mob_event, addr, :tap, nil}} =
               Bridge.legacy_to_canonical({:tap, {:user, 42}}, MyScreen)

      assert addr.id == {:user, 42}
    end

    test "widget kind can be overridden via opts" do
      assert {:ok, {:mob_event, addr, :tap, nil}} =
               Bridge.legacy_to_canonical({:tap, :submit}, MyScreen, widget: :pressable)

      assert addr.widget == :pressable
    end

    test "render_id is honored" do
      assert {:ok, {:mob_event, addr, :tap, nil}} =
               Bridge.legacy_to_canonical({:tap, :save}, MyScreen, render_id: 17)

      assert addr.render_id == 17
    end

    test "nil tag passes through (invalid id)" do
      assert :passthrough = Bridge.legacy_to_canonical({:tap, nil}, MyScreen)
    end

    test "pid tag passes through (invalid id)" do
      assert :passthrough = Bridge.legacy_to_canonical({:tap, self()}, MyScreen)
    end
  end

  describe "legacy_to_canonical/3 — list-row select" do
    test "structured list tag produces a list event with instance" do
      assert {:ok, {:mob_event, addr, :select, nil}} =
               Bridge.legacy_to_canonical({:tap, {:list, :contacts, :select, 47}}, MyScreen)

      assert addr.widget == :list
      assert addr.id == :contacts
      assert addr.instance == 47
    end

    test "list_id can be a binary (data-derived)" do
      assert {:ok, {:mob_event, addr, :select, nil}} =
               Bridge.legacy_to_canonical({:tap, {:list, "contacts", :select, 0}}, MyScreen)

      assert addr.id == "contacts"
    end

    test "list-row tap takes precedence over generic :tap rule" do
      # The structured shape must match before the generic {:tap, tag} clause.
      assert {:ok, {:mob_event, addr, :select, _}} =
               Bridge.legacy_to_canonical({:tap, {:list, :x, :select, 0}}, MyScreen)

      assert addr.widget == :list
      refute addr.widget == :button
    end
  end

  describe "legacy_to_canonical/3 — :change" do
    test "atom tag + binary value" do
      assert {:ok, {:mob_event, addr, :change, "user@example.com"}} =
               Bridge.legacy_to_canonical({:change, :email, "user@example.com"}, MyScreen)

      assert addr.widget == :text_field
      assert addr.id == :email
    end

    test "boolean value (toggle)" do
      assert {:ok, {:mob_event, addr, :change, true}} =
               Bridge.legacy_to_canonical({:change, :notifications, true}, MyScreen)

      assert addr.id == :notifications
    end

    test "float value (slider)" do
      assert {:ok, {:mob_event, _addr, :change, 0.75}} =
               Bridge.legacy_to_canonical({:change, :volume, 0.75}, MyScreen)
    end

    test "widget kind can be overridden" do
      assert {:ok, {:mob_event, addr, :change, _}} =
               Bridge.legacy_to_canonical({:change, :enabled, true}, MyScreen, widget: :toggle)

      assert addr.widget == :toggle
    end

    test "nil tag passes through" do
      assert :passthrough = Bridge.legacy_to_canonical({:change, nil, "x"}, MyScreen)
    end
  end

  describe "legacy_to_canonical/3 — passthrough" do
    test "unknown shapes pass through" do
      assert :passthrough = Bridge.legacy_to_canonical({:something_else, :x}, MyScreen)
      assert :passthrough = Bridge.legacy_to_canonical(:atom, MyScreen)
      assert :passthrough = Bridge.legacy_to_canonical("string", MyScreen)
      assert :passthrough = Bridge.legacy_to_canonical(nil, MyScreen)
    end

    test "already-canonical envelope is NOT re-wrapped (passes through)" do
      already =
        {:mob_event,
         %Address{screen: S, widget: :button, id: :x, component_path: [], instance: nil, render_id: 1},
         :tap, nil}

      assert :passthrough = Bridge.legacy_to_canonical(already, MyScreen)
    end
  end

  describe "legacy_to_canonical!/3" do
    test "returns envelope on success" do
      env = Bridge.legacy_to_canonical!({:tap, :save}, MyScreen)
      assert {:mob_event, %Address{id: :save}, :tap, nil} = env
    end

    test "raises on passthrough" do
      assert_raise ArgumentError, ~r/Not a recognized legacy event/, fn ->
        Bridge.legacy_to_canonical!({:not_an_event, :x}, MyScreen)
      end
    end
  end
end
