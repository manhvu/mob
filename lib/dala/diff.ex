defmodule Dala.Diff do
  @moduledoc """
  Diff engine for incremental UI updates.

  Compares two UI trees (as `Dala.Node` structs) and produces a minimal
  set of patches to transform the old tree into the new tree.

  ## Patch format

  Patches are tuples tagged with an action:

      {:replace, id, node}           # Replace entire node
      {:update_props, id, props}     # Update props on existing node
      {:insert, parent_id, index, node}  # Insert new node
      {:remove, id}                  # Remove node

  ## Usage

      old_tree = Dala.Node.from_map(old_map, "root")
      new_tree = Dala.Node.from_map(new_map, "root")
      patches = Dala.Diff.diff(old_tree, new_tree)

  ## Node identity

  Nodes are identified by the `:id` field in `Dala.Node`. This must be
  stable across renders for proper reconciliation.
  """

  alias Dala.Node

  @type node_id :: String.t() | atom()

  @type patch ::
          {:replace, node_id(), Node.t()}
          | {:update_props, node_id(), map()}
          | {:insert, node_id(), non_neg_integer(), Node.t()}
          | {:remove, node_id()}

  @doc """
  Compute the diff between two UI trees.

  Returns a list of patches to transform `old_tree` into `new_tree`.
  """
  @spec diff(Node.t() | nil, Node.t() | nil) :: [patch()]
  def diff(nil, %Node{id: id} = new), do: [{:replace, id, new}]
  def diff(%Node{id: id}, nil), do: [{:remove, id}]
  def diff(%Node{id: id} = old, %Node{id: id} = new), do: do_diff(old, new)

  def diff(%Node{id: old_id} = old, %Node{id: new_id} = new) do
    # Different IDs at root level - full replacement
    [{:remove, old_id}, {:insert, :root, 0, %Dala.Node{new | id: new_id}}]
  end

  # Same node - check for changes
  defp do_diff(%Node{id: id, type: type} = old, %Node{type: type} = new) do
    props_patches = diff_props(old, new)
    children_patches = diff_children(old, new)
    props_patches ++ children_patches
  end

  defp do_diff(%Node{id: id} = old, %Node{} = new) do
    # Different type - full replacement
    [{:replace, id, new}]
  end

  # Props diff - send full props when changed
  defp diff_props(%Node{id: id, props: old_props}, %Node{props: new_props}) do
    if old_props == new_props do
      []
    else
      [{:update_props, id, new_props}]
    end
  end

  # Children diff with keyed reconciliation
  defp diff_children(%Node{id: parent_id, children: old_children}, %Node{children: new_children}) do
    old_map = Map.new(old_children, &{&1.id, &1})
    new_map = Map.new(new_children, &{&1.id, &1})

    []
    |> diff_removed(old_map, new_map)
    |> diff_inserted(parent_id, old_map, new_children)
    |> diff_existing(old_map, new_map)
  end

  # Remove nodes that are in old but not in new
  defp diff_removed(patches, old_map, new_map) do
    Enum.reduce(old_map, patches, fn {id, _old_node}, acc ->
      if Map.has_key?(new_map, id) do
        acc
      else
        [{:remove, id} | acc]
      end
    end)
  end

  # Insert new nodes with correct index
  defp diff_inserted(patches, parent_id, old_map, new_children) do
    Enum.with_index(new_children)
    |> Enum.reduce(patches, fn {child, index}, acc ->
      if Map.has_key?(old_map, child.id) do
        acc
      else
        [{:insert, parent_id, index, child} | acc]
      end
    end)
  end

  # Diff existing nodes recursively
  defp diff_existing(patches, old_map, new_map) do
    Enum.reduce(new_map, patches, fn {id, new_node}, acc ->
      case Map.get(old_map, id) do
        nil ->
          acc

        old_node ->
          acc ++ diff(old_node, new_node)
      end
    end)
  end
end
