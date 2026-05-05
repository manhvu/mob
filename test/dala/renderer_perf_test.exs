defmodule Dala.RendererPerfTest do
  use ExUnit.Case, async: true
  import Dala.Renderer

  @moduledoc """
  Performance tests for Dala.Renderer module.
  """

  describe "Performance tests" do
    @tag :performance
    test "render/4 handles large trees (1000+ nodes)" do
      # Create a large tree with 1000 text nodes
      children =
        Enum.map(1..1000, fn i ->
          %{
            type: :text,
            props: %{text: "Node #{i}"},
            children: []
          }
        end)

      tree = %{
        type: :column,
        props: %{},
        children: children
      }

      start = System.monotonic_time(:millisecond)
      Dala.Renderer.render(tree, :android, MockNIF)
      {_, [json]} = Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root end)
      stop = System.monotonic_time(:millisecond)

      duration = stop - start
      # Should complete within 5 seconds for 1000 nodes
      assert duration < 5000, "render/4 took #{duration}ms for 1000 nodes"

      # Verify the JSON is valid
      decoded = Jason.decode!(json)
      assert decoded["type"] == "column"
      assert length(decoded["children"]) == 1000
    end

    test "render_fast/4 handles large trees efficiently" do
      # Create a large tree with tap handlers
      children =
        Enum.map(1..1000, fn i ->
          %{
            type: :button,
            props: %{text: "Button #{i}", on_tap: {self(), :"tap_#{i}"}},
            children: []
          }
        end)

      tree = %{
        type: :column,
        props: %{},
        children: children
      }

      start = System.monotonic_time(:millisecond)
      Dala.Renderer.render_fast(tree, :android, MockNIF)
      {_, [json]} = Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root end)
      stop = System.monotonic_time(:millisecond)

      duration = stop - start
      # render_fast should be faster due to batch tap registration
      assert duration < 5000, "render_fast/4 took #{duration}ms for 1000 nodes"

      # Verify the JSON is valid
      decoded = Jason.decode!(json)
      assert decoded["type"] == "column"
      assert length(decoded["children"]) == 1000
    end

    test "render/4 performance regression baseline" do
      # Simple tree (10 nodes) - baseline measurement
      children =
        Enum.map(1..10, fn i ->
          %{
            type: :text,
            props: %{text: "Node #{i}"},
            children: []
          }
        end)

      tree = %{
        type: :column,
        props: %{},
        children: children
      }

      # Warm-up run
      Dala.Renderer.render(tree, :android, MockNIF)

      # Timed runs
      times =
        Enum.map(1..5, fn _ ->
          MockNIF.reset()
          start = System.monotonic_time(:microsecond)
          Dala.Renderer.render(tree, :android, MockNIF)
          stop = System.monotonic_time(:microsecond)
          stop - start
        end)

      avg_time = Enum.sum(times) / length(times)
      IO.puts("Average render time for 10 nodes: #{avg_time}μs")

      # Baseline: should be under 1000μs (1ms) for 10 simple nodes
      assert avg_time < 1000, "Average render time #{avg_time}μs exceeds 1000μs baseline"
    end

    test "deep nesting won't cause stack overflow" do
      # Create a deeply nested tree (100 levels deep)
      tree = create_deep_tree(100, :text, %{text: "Deep"})

      start = System.monotonic_time(:millisecond)
      Dala.Renderer.render(tree, :android, MockNIF)
      {_, [json]} = Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root end)
      stop = System.monotonic_time(:millisecond)

      duration = stop - start
      assert duration < 5000, "Deep tree (100 levels) took #{duration}ms"

      decoded = Jason.decode!(json)
      assert decoded["type"] == "column"
    end

    test "wide tree (1000 children) performance" do
      # Create a very wide tree (flat, 1000 children)
      children =
        Enum.map(1..1000, fn i ->
          %{
            type: :text,
            props: %{text: "Wide #{i}"},
            children: []
          }
        end)

      tree = %{
        type: :column,
        props: %{},
        children: children
      }

      start = System.monotonic_time(:millisecond)
      Dala.Renderer.render(tree, :android, MockNIF)
      {_, [json]} = Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root end)
      stop = System.monotonic_time(:millisecond)

      duration = stop - start
      assert duration < 5000, "Wide tree (1000 children) took #{duration}ms"
      assert length(Jason.decode!(json)["children"]) == 1000
    end

    test "mixed component tree performance" do
      # Create a tree with different component types
      children =
        Enum.map(1..500, fn i ->
          case rem(i, 3) do
            0 ->
              %{type: :text, props: %{text: "Text #{i}"}, children: []}

            1 ->
              %{type: :button, props: %{text: "Btn #{i}", on_tap: {self(), :tap}}, children: []}

            _ ->
              %{type: :image, props: %{src: "img#{i}.jpg"}, children: []}
          end
        end)

      tree = %{
        type: :column,
        props: %{},
        children: children
      }

      start = System.monotonic_time(:millisecond)
      Dala.Renderer.render(tree, :android, MockNIF)
      {_, [json]} = Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root end)
      stop = System.monotonic_time(:millisecond)

      duration = stop - start
      assert duration < 5000, "Mixed tree (500 nodes) took #{duration}ms"
      assert length(Jason.decode!(json)["children"]) == 500
    end

    test "render with large text content" do
      # Create nodes with large text content
      children =
        Enum.map(1..100, fn i ->
          %{
            type: :text,
            props: %{text: String.duplicate("Large content ", 1000) <> " #{i}"},
            children: []
          }
        end)

      tree = %{
        type: :column,
        props: %{},
        children: children
      }

      start = System.monotonic_time(:millisecond)
      Dala.Renderer.render(tree, :android, MockNIF)
      {_, [json]} = Enum.find(MockNIF.calls(), fn {f, _} -> f == :set_root end)
      stop = System.monotonic_time(:millisecond)

      duration = stop - start
      assert duration < 5000, "Large text tree (100 nodes) took #{duration}ms"
    end
  end

  # Helper to create deeply nested tree
  defp create_deep_tree(0, type, props) do
    %{type: type, props: props, children: []}
  end

  defp create_deep_tree(depth, type, props) do
    %{
      type: :column,
      props: %{},
      children: [create_deep_tree(depth - 1, type, props)]
    }
  end
end
