defmodule Dala.DiffTest do
  use ExUnit.Case, async: true
  doctest Dala.Diff

  describe "diff/2" do
    test "returns empty list when trees are identical" do
      tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      assert Dala.Diff.diff(tree, tree) == []
    end

    test "detects prop changes" do
      old_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "World"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert [{:update_props, "root", %{text: "World"}}] = patches
    end

    test "detects type change as replace" do
      old_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :button,
        props: %{title: "Click"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert [{:replace, "root", %Dala.Node{type: :button}}] = patches
    end

    test "handles first render (nil old tree)" do
      new_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      patches = Dala.Diff.diff(nil, new_tree)
      assert [{:replace, "root", _}] = patches
    end

    test "detects child insertion" do
      old_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}, children: []}
        ]
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert Enum.any?(patches, fn {action, _, _, _} -> action == :insert end)
    end

    test "detects child removal" do
      old_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}, children: []}
        ]
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert Enum.any?(patches, fn {action, _} -> action == :remove end)
    end

    test "uses explicit IDs when provided" do
      old_tree = %Dala.Node{
        id: "my_text",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "my_text",
        type: :text,
        props: %{text: "World"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert [{:update_props, "my_text", %{text: "World"}}] = patches
    end

    test "handles different IDs at root" do
      old_tree = %Dala.Node{
        id: "old_root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "new_root",
        type: :text,
        props: %{text: "World"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert [{:remove, "old_root"}, {:insert, :root, 0, _}] = patches
    end
  end

  describe "binary protocol v2 encoder" do
    test "encode_frame produces valid header for remove patch" do
      patches = [{:remove, "test_id"}]
      binary = Dala.Renderer.encode_frame(patches)

      <<version::little-16, patch_count::little-16, _rest::binary>> = binary
      assert version == 1
      assert patch_count == 1
    end

    test "encode_frame produces valid header for insert patch" do
      node = %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}, children: []}
      patches = [{:insert, "root", 0, node}]
      binary = Dala.Renderer.encode_frame(patches)

      <<version::little-16, patch_count::little-16, _rest::binary>> = binary
      assert version == 1
      assert patch_count == 1
      assert byte_size(binary) > 6
    end

    test "encode_frame handles update_props patch" do
      patches = [{:update_props, "b1", %{title: "Click"}}]
      binary = Dala.Renderer.encode_frame(patches)

      <<version::little-16, patch_count::little-16, _rest::binary>> = binary
      assert version == 1
      assert patch_count == 1
      assert byte_size(binary) > 6
    end

    test "encode_frame handles multiple patches" do
      patches = [
        {:remove, "old_id"},
        {:insert, "root", 0, %Dala.Node{id: "new", type: :text, props: %{text: "Hi"}, children: []}}
      ]
      binary = Dala.Renderer.encode_frame(patches)

      <<version::little-16, patch_count::little-16, _rest::binary>> = binary
      assert version == 1
      assert patch_count == 2
    end

    test "encode_frame includes inline strings in insert" do
      node = %Dala.Node{id: "t1", type: :text, props: %{text: "Hello World"}, children: []}
      patches = [{:insert, "root", 0, node}]
      binary = Dala.Renderer.encode_frame(patches)

      # The string "Hello World" should appear inline in the binary
      assert binary =~ "Hello World"
    end

    test "encode_frame includes layout props" do
      node = %Dala.Node{id: "c1", type: :column, props: %{padding: 16.0, flex_direction: :row}, children: []}
      patches = [{:insert, "root", 0, node}]
      binary = Dala.Renderer.encode_frame(patches)

      <<_version::little-16, _count::little-16, _rest::binary>> = binary
      # Should encode without error and contain the padding float
      assert byte_size(binary) > 6
    end
  end
end
