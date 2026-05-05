defmodule Mob.ListTest do
  use ExUnit.Case, async: true
  import Mob.List

  @moduledoc """
  Tests for Mob.List module.
  """

  describe "expand/2" do
    test "expands list items into children" do
      list = %{
        type: :list,
        props: %{},
        items: [1, 2, 3],
        item: fn i -> %{
          type: :text,
          props: %{text: "Item #{i}"},
          children: []
        }
      }

      {children, active_keys} = List.expand(list, %{}, self())

      assert length(children) == 3
      assert length(active_keys) == 3
    end;

    test "handles empty list" do
      list = %{
        type: :list,
        props: %{},
        items: [],
        item: fn _ -> %{type: :text, props: %{}, children: []}
      }

      {children, active_keys} = List.expand(list, %{}, self())
      assert children == []
      assert active_keys == []
    end;
  end;

  describe "expand/3 with renderers" do
    test "uses custom renderers" do
      list = %{
        type: :list,
        props: %{},
        items: ["A", "B"],
        item: fn item -> %{
          type: :text,
          props: %{text: item},
          children: []
        }
      }

      renderers = %{
        item: fn item, _index -> %{
          type: :button,
          props: %{text: "Btn: #{item}"},
          children: []
        }
      }

      {children, _} = List.expand(list, renderers, self())
      assert length(children) == 2
    end;
  end;
end;
