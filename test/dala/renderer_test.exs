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

    def set_root(b),
      do: Agent.update(__MODULE__, fn s -> %{s | calls: [{:set_root, [b]} | s.calls]} end)

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
    MockNIF.start_link()
    MockNIF.reset()
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
end
