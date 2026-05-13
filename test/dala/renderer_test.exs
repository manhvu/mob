defmodule Dala.RendererTest do
  use ExUnit.Case, async: true
  alias Dala.Renderer

  # Mock NIF for testing
  defmodule MockNIF do
    use Agent

    def start_link, do: Agent.start_link(fn -> %{calls: [], tap_next: 0} end, name: __MODULE__)
    def reset, do: Agent.update(__MODULE__, fn _ -> %{calls: [], tap_next: 0} end)
    def calls, do: Agent.get(__MODULE__, & &1.calls)

    def clear_taps,
      do: Agent.update(__MODULE__, fn s -> %{s | calls: [{:clear_taps, []} | s.calls]} end)

    def set_transition(t),
      do: Agent.update(__MODULE__, fn s -> %{s | calls: [{:set_transition, [t]} | s.calls]} end)

    def set_root_binary(b),
      do: Agent.update(__MODULE__, fn s -> %{s | calls: [{:set_root_binary, [b]} | s.calls]} end)

    def set_taps(t),
      do: Agent.update(__MODULE__, fn s -> %{s | calls: [{:set_taps, [t]} | s.calls]} end)

    def apply_patches(b),
      do: Agent.update(__MODULE__, fn s -> %{s | calls: [{:apply_patches, [b]} | s.calls]} end)

    def register_tap(pid),
      do:
        Agent.get_and_update(__MODULE__, fn s ->
          {s.tap_next, %{s | calls: [{:register_tap, [pid]} | s.calls], tap_next: s.tap_next + 1}}
        end)
  end

  setup do
    case MockNIF.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> MockNIF.reset()
    end

    :ok
  end

  setup _context do
    on_exit(fn ->
      try do
        Agent.stop(MockNIF)
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  describe "render/3" do
    test "calls clear_taps before rendering" do
      tree = %{type: :column, props: %{}, children: []}
      Renderer.render(tree, :android, MockNIF)
      assert Enum.any?(MockNIF.calls(), fn {f, _} -> f == :clear_taps end)
    end

    test "calls set_root_binary with a binary" do
      tree = %{type: :column, props: %{}, children: []}
      Renderer.render(tree, :android, MockNIF)
      assert Enum.any?(MockNIF.calls(), fn {f, _} -> f == :set_root_binary end)
    end

    test "returns {:ok, :binary_tree}" do
      tree = %{type: :column, props: %{}, children: []}
      assert {:ok, :binary_tree} = Renderer.render(tree, :android, MockNIF)
    end
  end

  describe "render_fast/3" do
    test "calls clear_taps before rendering" do
      tree = %{type: :column, props: %{}, children: []}
      Renderer.render_fast(tree, :android, MockNIF)
      assert Enum.any?(MockNIF.calls(), fn {f, _} -> f == :clear_taps end)
    end

    test "calls set_root_binary with a binary" do
      tree = %{type: :column, props: %{}, children: []}
      Renderer.render_fast(tree, :android, MockNIF)
      assert Enum.any?(MockNIF.calls(), fn {f, _} -> f == :set_root_binary end)
    end

    test "returns {:ok, :binary_tree}" do
      tree = %{type: :column, props: %{}, children: []}
      assert {:ok, :binary_tree} = Renderer.render_fast(tree, :android, MockNIF)
    end
  end

  describe "render_patches/4 with field-mask patches" do
    test "sends patch_node patches via apply_patches" do
      old_tree = %{type: :text, props: %{text: "Hello"}, children: []}
      new_tree = %{type: :text, props: %{text: "World"}, children: []}

      {:ok, patches} = Renderer.render_patches(old_tree, new_tree, :android, MockNIF)

      # The diff should produce a patch (either update_props or patch_node)
      assert length(patches) >= 1
    end

    test "sends v3 binary frame for prop-only updates" do
      old_tree = %{type: :text, props: %{text: "Hello"}, children: []}
      new_tree = %{type: :text, props: %{text: "World"}, children: []}

      {:ok, _patches} = Renderer.render_patches(old_tree, new_tree, :android, MockNIF)

      # For prop-only updates, apply_patches should be called with binary data
      apply_patches_calls =
        Enum.filter(MockNIF.calls(), fn {f, _} -> f == :apply_patches end)

      if length(apply_patches_calls) > 0 do
        [{:apply_patches, [binary]}] = apply_patches_calls
        # Verify v3 header
        <<0xDA::8, 0xA1::8, version::little-16, _rest::binary>> = binary
        assert version == 3
      end
    end

    test "sends patches via apply_patches for structural changes" do
      old_tree = %{type: :column, props: %{}, children: []}

      new_tree = %{
        type: :column,
        props: %{},
        children: [%{type: :text, props: %{text: "Hi"}, children: []}]
      }

      {:ok, patches} = Renderer.render_patches(old_tree, new_tree, :android, MockNIF)

      # Structural changes produce insert patches
      assert length(patches) > 0

      assert Enum.any?(patches, fn
               {:insert, _, _, _} -> true
               _ -> false
             end)

      # Patches are sent via apply_patches as binary frame
      assert Enum.any?(MockNIF.calls(), fn {f, _} -> f == :apply_patches end)
    end

    test "returns empty patches when nothing changed" do
      tree = %{type: :text, props: %{text: "Same"}, children: []}
      {:ok, patches} = Renderer.render_patches(tree, tree, :android, MockNIF)
      assert patches == []
      # No NIF calls when nothing changed
      assert MockNIF.calls() == []
    end

    test "render_patches with nil old tree sends replace patch" do
      new_tree = %{type: :column, props: %{}, children: []}
      {:ok, patches} = Renderer.render_patches(nil, new_tree, :android, MockNIF)
      assert length(patches) > 0

      assert Enum.any?(patches, fn
               {:replace, _, _} -> true
               _ -> false
             end)
    end

    test "render_patches with nil new tree sends remove patch" do
      old_tree = %{type: :column, props: %{}, children: []}
      {:ok, patches} = Renderer.render_patches(old_tree, nil, :android, MockNIF)
      assert length(patches) > 0

      assert Enum.any?(patches, fn
               {:remove, _} -> true
               _ -> false
             end)
    end

    test "render_patches produces valid v3 binary frame" do
      old_tree = %{type: :text, props: %{text: "Hello"}, children: []}
      new_tree = %{type: :text, props: %{text: "World"}, children: []}

      {:ok, _patches} = Renderer.render_patches(old_tree, new_tree, :android, MockNIF)

      [{:apply_patches, [binary]}] =
        Enum.filter(MockNIF.calls(), fn {f, _} -> f == :apply_patches end)

      # v3 header: magic bytes + version
      <<0xDA::8, 0xA1::8, version::little-16, _rest::binary>> = binary
      assert version == 3
    end

    test "render_patches with deep tree produces correct patches" do
      old_tree = %{
        type: :column,
        props: %{},
        children: [
          %{
            type: :row,
            props: %{},
            children: [
              %{type: :text, props: %{text: "A"}, children: []},
              %{type: :text, props: %{text: "B"}, children: []}
            ]
          }
        ]
      }

      new_tree = %{
        type: :column,
        props: %{},
        children: [
          %{
            type: :row,
            props: %{},
            children: [
              %{type: :text, props: %{text: "A"}, children: []},
              %{type: :text, props: %{text: "Changed"}, children: []}
            ]
          }
        ]
      }

      {:ok, patches} = Renderer.render_patches(old_tree, new_tree, :android, MockNIF)
      # Should produce patches for the changed text node
      assert length(patches) > 0
    end

    test "render_patches with child removal produces remove patch" do
      old_tree = %{
        type: :column,
        props: %{},
        children: [
          %{type: :text, props: %{text: "Keep"}, children: []},
          %{type: :text, props: %{text: "Remove"}, children: []}
        ]
      }

      new_tree = %{
        type: :column,
        props: %{},
        children: [
          %{type: :text, props: %{text: "Keep"}, children: []}
        ]
      }

      {:ok, patches} = Renderer.render_patches(old_tree, new_tree, :android, MockNIF)

      assert Enum.any?(patches, fn
               {:remove, _} -> true
               _ -> false
             end)
    end

    test "render_patches with type change produces replace patch" do
      old_tree = %{type: :text, props: %{text: "Hello"}, children: []}
      new_tree = %{type: :button, props: %{text: "Hello"}, children: []}

      {:ok, patches} = Renderer.render_patches(old_tree, new_tree, :android, MockNIF)

      assert Enum.any?(patches, fn
               {:replace, _, _} -> true
               _ -> false
             end)
    end
  end

  describe "v3 binary encoding in render output" do
    test "render produces v3 binary tree header" do
      tree = %{type: :column, props: %{}, children: []}
      Renderer.render(tree, :android, MockNIF)

      {:set_root_binary, [binary]} =
        Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root_binary end)

      # v3 full tree header: [0xDA, 0xA1, version::little-16, flags::little-16, node_count::little-64]
      <<0xDA::8, 0xA1::8, version::little-16, _flags::little-16, node_count::little-64,
        _rest::binary>> = binary

      assert version == 3
      assert node_count == 1
    end

    test "render produces v3 binary with children" do
      tree = %{
        type: :column,
        props: %{},
        children: [
          %{type: :text, props: %{text: "Hello"}, children: []}
        ]
      }

      Renderer.render(tree, :android, MockNIF)

      {:set_root_binary, [binary]} =
        Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root_binary end)

      <<0xDA::8, 0xA1::8, version::little-16, _flags::little-16, node_count::little-64,
        _rest::binary>> = binary

      assert version == 3
      assert node_count == 2
    end

    test "render_fast produces v3 binary tree header" do
      tree = %{type: :column, props: %{}, children: []}
      Renderer.render_fast(tree, :android, MockNIF)

      {:set_root_binary, [binary]} =
        Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root_binary end)

      <<0xDA::8, 0xA1::8, version::little-16, _flags::little-16, node_count::little-64,
        _rest::binary>> = binary

      assert version == 3
      assert node_count == 1
    end
  end
end
