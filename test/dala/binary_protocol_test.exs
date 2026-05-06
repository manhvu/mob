defmodule Dala.BinaryProtocolTest do
  use ExUnit.Case, async: true
  alias Dala.Node
  alias Dala.Renderer

  describe "encode_tree/1" do
    test "encodes a simple text node" do
      node = %Node{
        id: "text1",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      binary = Renderer.encode_tree(node)
      assert is_binary(binary)
      assert byte_size(binary) > 10
    end

    test "encodes a node with children" do
      node = %Node{
        id: "root",
        type: :column,
        props: %{padding: 10},
        children: [
          %Node{id: "child1", type: :text, props: %{text: "Hello"}, children: []},
          %Node{id: "child2", type: :button, props: %{text: "Click"}, children: []}
        ]
      }

      binary = Renderer.encode_tree(node)
      assert is_binary(binary)
      # Should contain root + 2 children = 3 nodes
      # Header: version(2) + flags(2) + node_count(8) = 12 bytes
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 3
    end

    test "encodes patches via encode_frame" do
      patches = [
        {:remove, "old_node"},
        {:update_props, "node1", %{text: "Updated"}}
      ]

      binary = Renderer.encode_frame(patches)
      assert is_binary(binary)
      # Header: version(2) + patch_count(2) = 4 bytes
      <<1::little-16, patch_count::little-16, _rest::binary>> = binary
      assert patch_count == 2
    end
  end

  describe "roundtrip" do
    test "tree can be encoded and has valid structure" do
      node = %Node{
        id: "root",
        type: :column,
        props: %{padding: 10, background: "blue"},
        children: [
          %Node{id: "text1", type: :text, props: %{text: "Hello World"}, children: []}
        ]
      }

      binary = Renderer.encode_tree(node)
      assert is_binary(binary)
      # Verify header
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 2  # root + text1
    end
  end
end
