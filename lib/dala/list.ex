defmodule Dala.List do
  @moduledoc """
  Public API for list operations.

  This module delegates to `Dala.Ui.List` for list-related functionality.
  """

  alias Dala.Ui.List

  @doc """
  Register a custom item renderer for a list.

  `id` must match the `:id` prop on the `type: :list` node.
  `renderer` is a 1-arity function that receives one item and returns a node map.

  Call this from `mount/3` or `handle_info/2` — it is stored in `socket.__dala__`
  and picked up at render time.
  """
  @spec put_renderer(Dala.Socket.t(), atom(), (term() -> map())) :: Dala.Socket.t()
  defdelegate put_renderer(socket, id, renderer), to: Dala.Ui.List

  @doc """
  The default item renderer.

  Handles binaries, maps with `:label`/`:text`, and falls back to `inspect/1`
  for anything else.
  """
  @spec default_renderer(term()) :: map()
  defdelegate default_renderer(item), to: List

  @doc """
  Walk a render tree and expand all `type: :list` nodes into `lazy_list` nodes.

  Called internally by `Dala.Screen` before passing the tree to `Dala.Ui.Renderer`.
  `renderers` is the `list_renderers` map from `socket.__dala__`. `pid` is the
  screen process (used as the tap target for row-select events).
  """
  @spec expand(map(), map(), pid()) :: map()
  defdelegate expand(node, renderers, pid), to: List
end
