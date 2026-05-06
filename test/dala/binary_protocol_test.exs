defmodule Dala.BinaryProtocolTest do
  use ExUnit.Case, async: true
  alias Dala.Node
  alias Dala.Renderer
  alias Dala.Diff

  # Helper to build a deeply nested tree
  defp build_deep_tree(levels, id_prefix \\ "node") when levels <= 0 do
    %Node{id: "\#{id_prefix}_leaf", type: :text, props: %{text: "Leaf"}, children: []}
  end

  defp build_deep_tree(levels, id_prefix) do
    %Node{
      id: "\#{id_prefix}_\#{levels}",
      type: if(rem(levels, 2) == 0, do: :column, else: :row),
      props: %{padding: levels * 5.0},
      children: [build_deep_tree(levels - 1, id_prefix)]
    }
  end

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

      # Verify header
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 1
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
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 3
    end

    test "encodes nested children correctly" do
      node = %Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Node{
            id: "parent",
            type: :row,
            props: %{},
            children: [
              %Node{id: "child1", type: :text, props: %{text: "A"}, children: []},
              %Node{id: "child2", type: :text, props: %{text: "B"}, children: []}
            ]
          }
        ]
      }

      binary = Renderer.encode_tree(node)
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 4  # root + parent + child1 + child2
    end

    test "encodes all property types" do
      node = %Node{
        id: "node1",
        type: :button,
        props: %{
          text: "Click me",
          width: 100.0,
          height: 50.0,
          padding: 10.0,
          flex_grow: 1.0,
          flex_direction: :row,
          justify_content: :center,
          align_items: :center
        },
        children: []
      }

      binary = Renderer.encode_tree(node)
      assert is_binary(binary)
      assert byte_size(binary) > 50
    end

    test "encodes node type correctly" do
      types = [:column, :row, :text, :button, :image, :scroll, :webview]

      for type <- types do
        node = %Node{id: "test", type: type, props: %{}, children: []}
        binary = Renderer.encode_tree(node)
        assert is_binary(binary)
      end
    end
  end

  describe "encode_frame/1 (patches)" do
    test "encodes a simple patch list" do
      patches = [
        {:remove, "old_node"},
        {:update_props, "node1", %{text: "Updated"}}
      ]

      binary = Renderer.encode_frame(patches)
      assert is_binary(binary)
      <<1::little-16, patch_count::little-16, _rest::binary>> = binary
      assert patch_count == 2
    end

    test "encodes INSERT patch with node" do
      node = %Node{id: "new_node", type: :text, props: %{text: "New"}, children: []}
      patches = [{:insert, "parent", 0, node}]

      binary = Renderer.encode_frame(patches)
      assert is_binary(binary)
      <<1::little-16, 1::little-16, opcode::8, _rest::binary>> = binary
      assert opcode == 0x01  # INSERT opcode
    end

    test "encodes REMOVE patch" do
      patches = [{:remove, "node_to_remove"}]
      binary = Renderer.encode_frame(patches)

      <<1::little-16, 1::little-16, opcode::8, _rest::binary>> = binary
      assert opcode == 0x02  # REMOVE opcode
    end

    test "encodes UPDATE patch" do
      patches = [{:update_props, "node1", %{text: "Updated", color: "red"}}]
      binary = Renderer.encode_frame(patches)

      <<1::little-16, 1::little-16, opcode::8, _rest::binary>> = binary
      assert opcode == 0x03  # UPDATE opcode
    end

    test "encodes empty patch list" do
      binary = Renderer.encode_frame([])
      <<1::little-16, 0::little-16>> = binary
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
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 2  # root + text1
    end

    test "diff produces valid patches" do
      old_node = %Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Node{id: "text1", type: :text, props: %{text: "Old"}, children: []}
        ]
      }

      new_node = %Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Node{id: "text1", type: :text, props: %{text: "New"}, children: []}
        ]
      }

      patches = Diff.diff(old_node, new_node)
      assert length(patches) > 0

      # Should be able to encode the patches
      binary = Renderer.encode_frame(patches)
      assert is_binary(binary)
    end
  end

  describe "complex real-world scenarios" do
    test "deeply nested tree (5+ levels)" do
      # Build: root > col > row > col > row > text
      deep_tree = build_deep_tree(5)
      binary = Renderer.encode_tree(deep_tree)

      assert is_binary(binary)
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 6  # 5 levels + root
    end

    test "wide tree with many children (20+ nodes)" do
      children = Enum.map(1..25, fn i ->
        %Node{
          id: "child_\#{i}",
          type: :button,
          props: %{text: "Button \#{i}", width: 80.0 + i, height: 44.0},
          children: []
        }
      end)

      tree = %Node{
        id: "root",
        type: :column,
        props: %{padding: 16.0},
        children: children
      }

      binary = Renderer.encode_tree(tree)
      assert is_binary(binary)
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 26  # root + 25 children
      assert byte_size(binary) > 1000  # Should be substantial
    end

    test "tree with all property types on multiple nodes" do
      tree = %Node{
        id: "root",
        type: :column,
        props: %{
          padding: 16.0,
          background: "surface",
          flex_direction: :row,
          justify_content: :space_between,
          align_items: :center
        },
        children: [
          %Node{
            id: "text1",
            type: :text,
            props: %{
              text: "Hello World",
              width: 200.5,
              height: 50.25,
              color: "primary"
            },
            children: []
          },
          %Node{
            id: "input1",
            type: :text_field,
            props: %{
              text: "Type here",
              width: 300.0,
              padding: 12.0,
              flex_grow: 1.0
            },
            children: []
          },
          %Node{
            id: "btn1",
            type: :button,
            props: %{
              text: "Submit",
              width: 120.0,
              height: 44.0,
              background: "primary"
            },
            children: []
          }
        ]
      }

      binary = Renderer.encode_tree(tree)
      assert is_binary(binary)
      assert byte_size(binary) > 200
    end

    test "realistic login form UI tree" do
      tree = %Node{
        id: "login_screen",
        type: :column,
        props: %{
          padding: 24.0,
          background: "white",
          flex_direction: :column
        },
        children: [
          %Node{
            id: "title",
            type: :text,
            props: %{text: "Welcome Back", text_size: :xl, text_color: "black"},
            children: []
          },
          %Node{
            id: "spacer1",
            type: :spacer,
            props: %{size: 20.0},
            children: []
          },
          %Node{
            id: "email_field",
            type: :text_field,
            props: %{
              placeholder: "Email",
              width: 300.0,
              height: 50.0,
              padding: 12.0,
              border_width: 1.0,
              border_color: "gray"
            },
            children: []
          },
          %Node{
            id: "password_field",
            type: :text_field,
            props: %{
              placeholder: "Password",
              width: 300.0,
              height: 50.0,
              padding: 12.0,
              border_width: 1.0,
              border_color: "gray",
              secure: true
            },
            children: []
          },
          %Node{
            id: "login_btn",
            type: :button,
            props: %{
              text: "Log In",
              width: 300.0,
              height: 50.0,
              background: "blue",
              text_color: "white",
              on_tap: {self(), :login}
            },
            children: []
          },
          %Node{
            id: "forgot_link",
            type: :text,
            props: %{text: "Forgot Password?", text_color: "blue", on_tap: {self(), :forgot}},
            children: []
          }
        ]
      }

      binary = Renderer.encode_tree(tree)
      assert is_binary(binary)
      <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
      assert node_count == 7  # root + 6 children
      assert byte_size(binary) > 250
    end

    test "unicode text encoding (emoji, CJK, accents)" do
      tree = %Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Node{
            id: "emoji",
            type: :text,
            props: %{text: "Hello 🎉 Welcome! 🚀"},
            children: []
          },
          %Node{
            id: "cjk",
            type: :text,
            props: %{text: "你好世界 こんにちは 안녕하세요"},
            children: []
          },
          %Node{
            id: "accents",
            type: :text,
            props: %{text: "Café naïve résumé"},
            children: []
          }
        ]
      }

      binary = Renderer.encode_tree(tree)
      assert is_binary(binary)
      # Should handle UTF-8 properly
      assert byte_size(binary) > 100
    end

    test "large patch frame with mixed operations" do
      patches = [
        {:remove, "old_header"},
        {:update_props, "title", %{text: "New Title", color: "red", font_size: 24.0}},
        {:insert, "main", 0, %Node{
          id: "new_section",
          type: :column,
          props: %{padding: 16.0},
          children: [
            %Node{id: "item1", type: :text, props: %{text: "Item 1"}, children: []},
            %Node{id: "item2", type: :text, props: %{text: "Item 2"}, children: []}
          ]
        }},
        {:update_props, "footer", %{background: "gray", height: 60.0}},
        {:remove, "old_banner"}
      ]

      binary = Renderer.encode_frame(patches)
      assert is_binary(binary)
      <<1::little-16, patch_count::little-16, _rest::binary>> = binary
      assert patch_count == 5
      assert byte_size(binary) > 100
    end

    test "rapid successive encodings (no state corruption)" do
      for i <- 1..10 do
        tree = %Node{
          id: "root_\#{i}",
          type: :column,
          props: %{padding: i * 1.0},
          children: Enum.map(1..5, fn j ->
            %Node{
              id: "child_\#{i}_\#{j}",
              type: :text,
              props: %{text: "Node \#{i}-\#{j}"},
              children: []
            }
          end)
        }

        binary = Renderer.encode_tree(tree)
        assert is_binary(binary)
        <<2::little-16, 0::little-16, node_count::little-64, _rest::binary>> = binary
        assert node_count == 6  # root + 5 children
      end
    end
  end
end
