defmodule Dala.Renderer do
  @moduledoc """
  Serializes a component tree to a binary command stream and passes it to the
  platform NIF in a single call. Compose (Android) and SwiftUI (iOS) handle
  diffing and rendering internally.

  ## Node format

      %{
        type: :column,
        props: %{padding: :space_md, background: :surface},
        children: [
          %{type: :text,   props: %{text: "Hello", text_size: :xl, text_color: :on_surface}, children: []},
          %{type: :button, props: %{text: "Tap", on_tap: self()},    children: []}
        ]
      }

  ## Token resolution

  Atom values for color props, spacing props, radius props, and text sizes are
  resolved at render time through the active `Dala.Theme` and the base palette.

  ## Component defaults

  When a component's props omit styling keys, the renderer injects sensible
  defaults from the active theme. Explicit props always win over defaults.

  ## Platform blocks

  Props scoped to one platform are silently ignored on the other:

      props: %{padding: 12, ios: %{padding: 20}}
      # iOS sees padding: 20; Android sees padding: 12

  ## Injecting a mock NIF

      Dala.Renderer.render(tree, :android, MockNIF)

  ## Binary protocol

  See `Dala.Renderer` module docs and `guides/binary_protocol.md` for the full
  binary protocol specification (v3).
  """

  alias Dala.Ui.Renderer

  @default_nif Dala.Platform.Native

  @doc """
  Render a UI tree for the given platform.
  """
  @spec render(Dala.Node.t() | map(), atom(), term(), atom()) ::
          {:ok, :binary_tree} | {:error, term()}
  def render(tree, platform, nif \\ @default_nif, transition \\ :none)

  def render(%Dala.Node{} = tree, platform, nif, transition) do
    Renderer.render(tree, platform, nif, transition)
  end

  def render(tree, platform, nif, transition) when is_map(tree) do
    Renderer.render(tree, platform, nif, transition)
  end

  @doc """
  Fast render path for simple updates.
  """
  @spec render_fast(Dala.Node.t() | map(), atom(), term(), atom()) ::
          {:ok, :binary_tree} | {:error, term()}
  def render_fast(tree, platform, nif \\ @default_nif, transition \\ :none)

  def render_fast(%Dala.Node{} = tree, platform, nif, transition) do
    Renderer.render_fast(tree, platform, nif, transition)
  end

  def render_fast(tree, platform, nif, transition) when is_map(tree) do
    Renderer.render_fast(tree, platform, nif, transition)
  end

  @doc """
  Compute patches between old and new trees.
  """
  @spec render_patches(Dala.Node.t() | map() | nil, Dala.Node.t() | map(), atom(), term(), atom()) ::
          {:ok, [Dala.Diff.patch()]} | {:error, term()}
  def render_patches(old_tree, new_tree, platform, nif \\ @default_nif, transition \\ :none)

  def render_patches(old_tree, new_tree, platform, nif, transition)
      when (is_map(old_tree) or is_nil(old_tree)) and is_map(new_tree) do
    Renderer.render_patches(old_tree, new_tree, platform, nif, transition)
  end

  def render_patches(%Dala.Node{} = old_tree, %Dala.Node{} = new_tree, platform, nif, transition) do
    Renderer.render_patches(old_tree, new_tree, platform, nif, transition)
  end

  def render_patches(nil, %Dala.Node{} = new_tree, platform, nif, transition) do
    Renderer.render_patches(nil, new_tree, platform, nif, transition)
  end

  def render_patches(old_tree, nil, platform, nif, transition)
      when is_map(old_tree) or is_nil(old_tree) do
    Renderer.render_patches(old_tree, nil, platform, nif, transition)
  end

  @doc """
  Encode patches to binary frame format for the native side.
  """
  @spec encode_frame([Dala.Diff.patch()]) :: binary()
  defdelegate encode_frame(patches), to: Renderer

  @doc """
  Get available colors from theme.
  """
  @spec colors() :: map()
  defdelegate colors(), to: Renderer

  @doc """
  Get text sizes from theme.
  """
  @spec text_sizes() :: map()
  defdelegate text_sizes(), to: Renderer
end
