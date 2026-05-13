defmodule Dala.Ui.Diff do
  import Bitwise

  @moduledoc """
  Diff engine for incremental UI updates.

  Compares two UI trees (as `Dala.Node` structs) and produces a minimal
  set of patches to transform the old tree into the new tree.

  ## Patch format

  Patches are tuples tagged with an action:

      {:replace, id, node}           # Replace entire node
      {:update_props, id, props}     # Update props on existing node (full replacement)
      {:patch_node, id, mask, props}  # Patch only changed fields (field-mask based)
      {:insert, parent_id, index, node}  # Insert new node
      {:remove, id}                  # Remove node

  ## Usage

      old_tree = Dala.Node.from_map(old_map, "root")
      new_tree = Dala.Node.from_map(new_map, "root")
      patches = Dala.Diff.diff(old_tree, new_tree)

  ## Node identity

  Nodes are identified by the `:id` field in `Dala.Node`. This must be
  stable across renders for proper reconciliation.

  ## Field masks

  When only a few props change, `{:patch_node, id, mask, props}` is emitted
  instead of `{:update_props, id, props}`. The mask is a 16-bit bitmask
  where bit N corresponds to field tag (N+1). If more than half the fields
  changed, a full `{:update_props, ...}` is sent instead.
  """

  # Auto-generated from Dala.Ui.Component registry
  # Limited to original 12 props that participate in field masks

  @original_mask_props [
    :text,
    :title,
    :color,
    :background,
    :on_tap,
    :width,
    :height,
    :padding,
    :flex_grow,
    :flex_direction,
    :justify_content,
    :align_items
  ]

  @field_mask_bits @original_mask_props
                   |> Enum.with_index()
                   |> Enum.map(fn {prop, idx} -> {prop, 1 <<< idx} end)
                   |> Map.new()

  @known_props @original_mask_props

  @type node_id :: String.t() | atom()

  @type patch ::
          {:replace, node_id(), Dala.Node.t()}
          | {:update_props, node_id(), map()}
          | {:patch_node, node_id(), non_neg_integer(), map()}
          | {:insert, node_id(), non_neg_integer(), Dala.Node.t()}
          | {:remove, node_id()}

  @doc """
  Compute the diff between two UI trees.

  Returns a list of patches to transform `old_tree` into `new_tree`.
  """
  @spec diff(Dala.Node.t() | nil, Dala.Node.t() | nil) :: [patch()]
  def diff(nil, %Dala.Node{id: id} = new), do: [{:replace, id, new}]
  def diff(%Dala.Node{id: id}, nil), do: [{:remove, id}]
  def diff(%Dala.Node{id: id} = old, %Dala.Node{id: id} = new), do: do_diff(old, new)

  def diff(%Dala.Node{id: old_id} = _old, %Dala.Node{id: new_id} = new) do
    # Different IDs at root level - full replacement
    [{:remove, old_id}, {:insert, :root, 0, %Dala.Node{new | id: new_id}}]
  end

  # Same node - check for changes
  defp do_diff(%Dala.Node{id: _id, type: type} = old, %Dala.Node{type: type} = new) do
    props_patches = diff_props(old, new)
    children_patches = diff_children(old, new)
    props_patches ++ children_patches
  end

  defp do_diff(%Dala.Node{id: id} = _old, %Dala.Node{} = new) do
    # Different type - full replacement
    [{:replace, id, new}]
  end

  # Props diff - use field-mask based patching when few fields changed,
  # full update when many fields changed
  defp diff_props(%Dala.Node{id: id, props: old_props}, %Dala.Node{props: new_props}) do
    if old_props == new_props do
      []
    else
      {mask, changed} = compute_field_mask(old_props, new_props)
      known_count = Enum.count(@known_props, &Map.has_key?(new_props, &1))
      changed_count = map_size(changed)

      # If more than half the known fields changed, send full update
      if known_count > 0 and changed_count > known_count / 2 do
        [{:update_props, id, new_props}]
      else
        [{:patch_node, id, mask, changed}]
      end
    end
  end

  @doc """
  Compute a field mask and changed props map from old and new props.

  Returns a `{mask, changed_map}` tuple where `mask` is a 16-bit bitmask
  and `changed_map` contains only the props that differ.
  """
  @spec compute_field_mask(map(), map()) :: {non_neg_integer(), map()}
  def compute_field_mask(old_props, new_props) when is_map(old_props) and is_map(new_props) do
    all_keys = MapSet.union(MapSet.new(Map.keys(old_props)), MapSet.new(Map.keys(new_props)))

    Enum.reduce(all_keys, {0, %{}}, fn key, {mask, changed} ->
      old_val = Map.get(old_props, key)
      new_val = Map.get(new_props, key)

      if old_val != new_val do
        bit = Map.get(@field_mask_bits, key, 0)

        if bit != 0 do
          {mask ||| bit, Map.put(changed, key, new_val)}
        else
          # Unknown prop key — include in changed map but no mask bit
          {mask, Map.put(changed, key, new_val)}
        end
      else
        {mask, changed}
      end
    end)
  end

  # Children diff with keyed reconciliation
  defp diff_children(%Dala.Node{id: parent_id, children: old_children}, %Dala.Node{
         children: new_children
       }) do
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
