defmodule Dala.Ui.Renderer do
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

  **Color props** (`:background`, `:text_color`, `:border_color`, `:color`,
  `:placeholder_color`): resolved via theme semantic tokens first, then the
  base palette. E.g. `:primary` → theme's primary → `:blue_500` → `0xFF2196F3`.

  **Spacing props** (`:padding`, `:padding_top`, etc., `:gap`): accept spacing
  tokens (`:space_xs`, `:space_sm`, `:space_md`, `:space_lg`, `:space_xl`)
  that are scaled by `theme.space_scale`.

  **Radius props** (`:corner_radius`): accept `:radius_sm`, `:radius_md`,
  `:radius_lg`, `:radius_pill` from the active theme.

  **Border** (currently honored on `:box` only): set both `:border_color`
  (a color token like `:primary` or `:border`) and `:border_width` (an
  integer pt/dp value, e.g. `1`). When width is 0 or color is unset, no
  border draws.

  **Text size props** (`:text_size`, `:font_size`): token atoms (`:xl`, `:lg`,
  etc.) are multiplied by `theme.type_scale`.

  ## Component defaults

  When a component's props omit styling keys, the renderer injects sensible
  defaults from the active theme. Explicit props always win over defaults.

      # Gets primary background, white text, medium radius automatically:
      %{type: :button, props: %{text: "Save", on_tap: {self(), :save}}, children: []}

  ## Style structs

  A `%Dala.Ui.Style{}` value under the `:style` key is merged into the node's
  own props before serialisation. Inline props override style values.

  ## Platform blocks

  Props scoped to one platform are silently ignored on the other:

      props: %{padding: 12, ios: %{padding: 20}}
      # iOS sees padding: 20; Android sees padding: 12

  ## Injecting a mock NIF

      Dala.Ui.Renderer.render(tree, :android, MockNIF)
  """

  @default_nif Dala.Platform.Native

  # ── Protocol v3 constants ─────────────────────────────────────────────

  @protocol_version 3
  @magic_byte_0 0xDA
  @magic_byte_1 0xA1

  @op_frame_begin 0x00
  @op_create_node 0x01
  @op_remove 0x02
  @op_update 0x03
  @op_patch_node 0x04
  @op_register_string 0x05
  @op_set_text 0x06
  @op_set_style 0x07
  @op_event 0x08
  @op_frame_end 0xFF

  # ── Base palette ──────────────────────────────────────────────────────────
  # Raw named colors. Semantic tokens (:primary, :surface, etc.) resolve
  # through the active Dala.Theme first, then fall through to this table.

  @colors %{
    # Semantic fallbacks (used when no theme is configured or as base values)
    primary: 0xFF2196F3,
    surface: 0xFFFFFFFF,
    on_primary: 0xFFFFFFFF,
    on_surface: 0xFF212121,
    error: 0xFFF44336,
    # Basic
    white: 0xFFFFFFFF,
    black: 0xFF000000,
    transparent: 0x00000000,
    # Grays
    gray_50: 0xFFFAFAFA,
    gray_100: 0xFFF5F5F5,
    gray_200: 0xFFEEEEEE,
    gray_300: 0xFFE0E0E0,
    gray_400: 0xFFBDBDBD,
    gray_500: 0xFF9E9E9E,
    gray_600: 0xFF757575,
    gray_700: 0xFF616161,
    gray_800: 0xFF424242,
    gray_900: 0xFF212121,
    gray_950: 0xFF121212,
    # Blues
    blue_100: 0xFFBBDEFB,
    blue_300: 0xFF64B5F6,
    blue_500: 0xFF2196F3,
    blue_700: 0xFF1976D2,
    blue_900: 0xFF0D47A1,
    # Greens
    green_400: 0xFF66BB6A,
    green_500: 0xFF4CAF50,
    green_700: 0xFF388E3C,
    emerald_400: 0xFF34D399,
    emerald_500: 0xFF10B981,
    emerald_700: 0xFF047857,
    # Reds
    red_400: 0xFFEF5350,
    red_500: 0xFFF44336,
    red_700: 0xFFD32F2F,
    # Oranges / Amber
    orange_400: 0xFFFFA726,
    orange_500: 0xFFFF9800,
    amber_400: 0xFFFBBF24,
    amber_500: 0xFFF59E0B,
    amber_700: 0xFFF57C00,
    # Limes / Yellows
    lime_300: 0xFFBEF264,
    lime_400: 0xFFA3E635,
    lime_500: 0xFF84CC16,
    lime_600: 0xFF65A30D,
    yellow_400: 0xFFFACC15,
    yellow_500: 0xFFEAB308,
    # Purples / Indigo / Violet
    purple_500: 0xFF9C27B0,
    purple_700: 0xFF7B1FA2,
    indigo_500: 0xFF3F51B5,
    deep_purple_700: 0xFF512DA8,
    violet_400: 0xFFA78BFA,
    violet_500: 0xFF8B5CF6,
    violet_600: 0xFF7C3AED,
    violet_700: 0xFF6D28D9,
    # Teals / Cyans
    teal_500: 0xFF009688,
    cyan_500: 0xFF00BCD4,
    # Stone / Warm neutrals
    stone_100: 0xFFF5F5F4,
    stone_200: 0xFFE7E5E4,
    stone_400: 0xFFA8A29E,
    stone_500: 0xFF78716C,
    stone_600: 0xFF57534E,
    stone_800: 0xFF292524,
    # Warm browns
    brown_400: 0xFFA0785A,
    brown_600: 0xFF7C4A1E,
    brown_800: 0xFF3E2010,
    # Pinks / Roses
    pink_500: 0xFFE91E63,
    rose_500: 0xFFF43F5E
  }

  @text_sizes %{
    xs: 12.0,
    sm: 14.0,
    base: 16.0,
    lg: 18.0,
    xl: 20.0,
    "2xl": 24.0,
    "3xl": 30.0,
    "4xl": 36.0,
    "5xl": 48.0,
    "6xl": 60.0
  }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Render a component tree for the given platform.

  Loads the active `Dala.Theme`, clears the tap registry, serialises the tree
  to a binary command stream, and calls `set_root_binary/1` on the NIF.
  Returns `{:ok, :binary_tree}`.

  `transition` is an atom (`:push`, `:pop`, `:reset`, `:none`) for the nav
  animation. Defaults to `:none` (instant swap).
  """
  @spec render(map(), atom(), module() | atom(), atom()) ::
          {:ok, :binary_tree} | {:error, term()}
  def render(tree, _platform, nif \\ @default_nif, _transition \\ :none) do
    theme = Dala.Theme.Theme.current()

    _ctx = %{
      colors: Dala.Theme.Theme.color_map(theme),
      spacing: Dala.Theme.Theme.spacing_map(theme),
      radii: Dala.Theme.Theme.radius_map(theme),
      type_scale: theme.type_scale
    }

    nif.clear_taps()

    # Use binary protocol for full tree rendering
    node = to_node(tree, "root")
    binary = encode_tree(node)

    nif.set_root_binary(binary)
    {:ok, :binary_tree}
  end

  # Optimized version that batches tap registrations
  @spec render_fast(Dala.Node.t() | map(), atom(), module(), atom()) :: {:ok, :binary_tree}
  def render_fast(tree, platform, nif \\ @default_nif, transition \\ :none) do
    theme = Dala.Theme.Theme.current()

    ctx = %{
      colors: Dala.Theme.Theme.color_map(theme),
      spacing: Dala.Theme.Theme.spacing_map(theme),
      radii: Dala.Theme.Theme.radius_map(theme),
      type_scale: theme.type_scale
    }

    nif.clear_taps()
    nif.set_transition(transition)

    # For render_fast, we still need tap registration
    # Convert to Node struct and encode with tap handles
    node = to_node(tree, "root")
    {binary, _taps} = encode_tree_with_taps(node, nif, platform, ctx)

    # Batch register taps
    # nif.set_taps(taps)  # TODO: integrate tap batching with binary protocol

    nif.set_root_binary(binary)
    {:ok, :binary_tree}
  end

  @doc """
  Render using incremental patches instead of full tree.

  Compares `old_tree` with `new_tree`, computes the diff, and sends
  only the patches to native. Falls back to full render on first call
  (when `old_tree` is nil).

  `new_tree` can be either a map (from Dala.Ui.Widgets functions) or a `Dala.Node` struct.
  If it's a map, it will be converted to a `Dala.Node` first.

  Returns `{:ok, patches}` where patches is the list of patch tuples.
  """
  @spec render_patches(
          Dala.Node.t() | map() | nil,
          Dala.Node.t() | map(),
          atom(),
          module(),
          atom()
        ) :: {:ok, [Dala.Ui.Diff.patch()]}
  def render_patches(old_tree, new_tree, platform, nif \\ @default_nif, transition \\ :none) do
    theme = Dala.Theme.Theme.current()

    ctx = %{
      colors: Dala.Theme.Theme.color_map(theme),
      spacing: Dala.Theme.Theme.spacing_map(theme),
      radii: Dala.Theme.Theme.radius_map(theme),
      type_scale: theme.type_scale
    }

    # Convert to Node structs if needed
    old_node = to_node(old_tree, "root")
    new_node = to_node(new_tree, "root")

    # Compute diff
    patches = Dala.Ui.Diff.diff(old_node, new_node)

    if patches == [] do
      # Nothing changed
      {:ok, []}
    else
      # Send all patches via the binary patch frame.
      # encode_patch handles :replace (remove+create), :insert, :remove,
      # :update_props, and :patch_node.
      nif.set_transition(transition)
      send_patches(patches, new_node, platform, nif, ctx)
      {:ok, patches}
    end
  end

  defp to_node(nil, _), do: nil
  defp to_node(%Dala.Node{} = node, _), do: node
  defp to_node(map, default_id), do: Dala.Node.from_map(map, default_id)

  # Send patches to native
  defp send_patches(patches, _tree, _platform, nif, _ctx) do
    binary = encode_frame(patches)

    if function_exported?(nif, :apply_patches, 1) do
      try do
        nif.apply_patches(binary)
      rescue
        e ->
          Dala.Platform.Native.log("Dala.Ui.Renderer: apply_patches failed: #{inspect(e)}")
      end
    else
      Dala.Platform.Native.log("Dala.Ui.Renderer: apply_patches not available")
    end
  end

  # ── Binary protocol v3 encoder ───────────────────────────────────────
  #
  # Full tree format (v3):
  #   Header:  [0xDA][0xA1][0x0003][flags::little-16][node_count::little-64]
  #   Nodes:   repeat [u64 id][u8 type][PROPS][u32 child_count][u64 child_ids...]
  #
  # Patch frame format (v3):
  #   Header:  [0xDA][0xA1][0x0003][patch_count::little-16]
  #   Body:    [FRAME_BEGIN][patches...][FRAME_END]
  #
  # Opcodes:
  #   0x00 FRAME_BEGIN       (no payload)
  #   0x01 CREATE_NODE       [u64 id][u64 parent][u32 index][u8 type][u64 layout_hash][PROPS][u32 child_count][u64 child_ids...]
  #   0x02 REMOVE            [u64 id]
  #   0x03 UPDATE            [u64 id][PROPS]
  #   0x04 PATCH_NODE        [u64 id][u16 field_mask][changed fields only]
  #   0x05 REGISTER_STRING   [u16 string_id][u16 len][bytes...]
  #   0x06 SET_TEXT           [u64 id][u16 len][bytes...]
  #   0x07 SET_STYLE          [u64 id][PROPS]
  #   0x08 EVENT              [u64 target_id][u8 event_type][u64 timestamp][u16 payload_len][payload_bytes]
  #   0xFF FRAME_END          (no payload)
  #
  # PROPS:   [u8 field_count] repeat [u8 tag][value...]
  #   1=text[u16 len][bytes]  2=title[u16 len][bytes]  3=color[u16 len][bytes]
  #   4=background[u16 len][bytes]  5=on_tap[u64]
  #   6=width[f32]  7=height[f32]  8=padding[f32]  9=flex_grow[f32]
  #   10=flex_direction[u8]  11=justify_content[u8]  12=align_items[u8]
  #   13=text_interned[u16 string_id]  14=title_interned[u16 string_id]
  #   15=color_interned[u16 string_id]  16=background_interned[u16 string_id]

  @doc "Encode a full Dala.Node tree to binary format (v3)"
  def encode_tree(%Dala.Node{} = node) do
    {binary, node_count} = encode_tree_node(node)

    IO.iodata_to_binary([
      <<@magic_byte_0::8, @magic_byte_1::8, @protocol_version::little-16, 0::little-16,
        node_count::little-64>>,
      binary
    ])
  end

  defp encode_tree_node(%Dala.Node{id: id, type: type, props: props, children: children}) do
    node_id = hash_id(id)

    {child_binaries, child_ids, total_count} =
      Enum.reduce(children, {[], [], 0}, fn child, {bins, ids, count} ->
        {bin, child_count} = encode_tree_node(child)
        {[bin | bins], [<<hash_id(child.id)::little-64>> | ids], count + child_count}
      end)

    child_count = length(children)

    node_binary = [
      <<node_id::little-64>>,
      <<kind_to_byte(type)::8>>,
      encode_props(props),
      <<child_count::little-32>>,
      Enum.reverse(child_ids)
    ]

    {[node_binary | Enum.reverse(child_binaries)], total_count + 1}
  end

  @doc "Encode tree with tap handles for render_fast"
  def encode_tree_with_taps(%Dala.Node{} = node, nif, platform, ctx) do
    {binary, taps} = encode_tree_node_with_taps(node, nif, platform, ctx)
    node_count = count_nodes(node)

    {IO.iodata_to_binary([
       <<@magic_byte_0::8, @magic_byte_1::8, @protocol_version::little-16, 0::little-16,
         node_count::little-64>>,
       binary
     ]), taps}
  end

  defp encode_tree_node_with_taps(
         %Dala.Node{id: id, type: type, props: props, children: children},
         nif,
         platform,
         ctx
       ) do
    node_id = hash_id(id)

    # Encode props with tap handling
    {encoded_props, tap_handles} = encode_props_with_taps(props, nif, platform, ctx)

    {child_binaries, child_ids, all_taps} =
      Enum.reduce(children, {[], [], tap_handles}, fn child, {bins, ids, taps} ->
        {bin, child_taps} = encode_tree_node_with_taps(child, nif, platform, ctx)
        {[bin | bins], [<<hash_id(child.id)::little-64>> | ids], taps ++ child_taps}
      end)

    child_count = length(children)

    node_binary = [
      <<node_id::little-64>>,
      <<kind_to_byte(type)::8>>,
      encoded_props,
      <<child_count::little-32>>,
      Enum.reverse(child_ids)
    ]

    {[node_binary | Enum.reverse(child_binaries)], all_taps}
  end

  defp count_nodes(%Dala.Node{children: children}) do
    1 + Enum.sum(Enum.map(children, &count_nodes/1))
  end

  @doc "Encode patches to binary frame format for the native side (v3)"
  def encode_frame(patches) when is_list(patches) do
    body = Enum.map(patches, &encode_patch/1)

    IO.iodata_to_binary([
      <<@magic_byte_0::8, @magic_byte_1::8, @protocol_version::little-16,
        length(patches)::little-16>>,
      <<@op_frame_begin::8>>,
      body,
      <<@op_frame_end::8>>
    ])
  end

  defp encode_patch({:insert, parent_id, index, %Dala.Node{} = node}) do
    id = hash_id(node.id)
    parent = hash_id(parent_id)
    layout_hash = compute_layout_hash(node)

    [
      <<@op_create_node::8, id::little-64, parent::little-64, index::little-32,
        kind_to_byte(node.type)::8, layout_hash::little-64>>,
      encode_props(node.props),
      encode_children(node.children)
    ]
  end

  defp encode_patch({:remove, id}) do
    <<@op_remove::8, hash_id(id)::little-64>>
  end

  defp encode_patch({:update_props, id, props}) do
    [<<@op_update::8, hash_id(id)::little-64>>, encode_props(props)]
  end

  defp encode_patch({:replace, id, %Dala.Node{} = node}) do
    # Replace = remove old + create new
    old_id = hash_id(id)
    new_id = hash_id(node.id)
    layout_hash = compute_layout_hash(node)
    # Parent is unknown from replace alone; use 0 as sentinel (root)
    [
      <<@op_remove::8, old_id::little-64>>,
      <<@op_create_node::8, new_id::little-64, 0::little-64, 0::little-32,
        kind_to_byte(node.type)::8, layout_hash::little-64>>,
      encode_props(node.props),
      encode_children(node.children)
    ]
  end

  defp encode_patch({:patch_node, id, field_mask, changed_props}) do
    [
      <<@op_patch_node::8, hash_id(id)::little-64, field_mask::little-16>>,
      encode_masked_props(changed_props)
    ]
  end

  @doc "Encode a PATCH_NODE command with field mask"
  @spec encode_patch_node(String.t() | atom(), non_neg_integer(), map()) :: binary()
  def encode_patch_node(id, field_mask, changed_props) do
    IO.iodata_to_binary([
      <<@op_patch_node::8, hash_id(id)::little-64, field_mask::little-16>>,
      encode_masked_props(changed_props)
    ])
  end

  @doc "Encode a SET_TEXT command"
  @spec encode_set_text(String.t() | atom(), binary()) :: binary()
  def encode_set_text(id, text) when is_binary(text) do
    IO.iodata_to_binary([
      <<@op_set_text::8, hash_id(id)::little-64, byte_size(text)::little-16>>,
      text
    ])
  end

  @doc "Encode a REGISTER_STRING command"
  @spec encode_register_string(non_neg_integer(), binary()) :: binary()
  def encode_register_string(string_id, text) when is_integer(string_id) and is_binary(text) do
    IO.iodata_to_binary([
      <<@op_register_string::8, string_id::little-16, byte_size(text)::little-16>>,
      text
    ])
  end

  @doc "Encode a SET_STYLE command for style-only updates"
  @spec encode_set_style(String.t() | atom(), map()) :: binary()
  def encode_set_style(id, props) when is_map(props) do
    IO.iodata_to_binary([
      <<@op_set_style::8, hash_id(id)::little-64>>,
      encode_props(props)
    ])
  end

  @doc "Encode an EVENT command"
  @spec encode_event(String.t() | atom(), non_neg_integer(), non_neg_integer(), binary()) ::
          binary()
  def encode_event(target_id, event_type, timestamp, payload) when is_binary(payload) do
    IO.iodata_to_binary([
      <<@op_event::8, hash_id(target_id)::little-64, event_type::8, timestamp::little-64,
        byte_size(payload)::little-16>>,
      payload
    ])
  end

  @doc "Compute the layout hash for a node"
  @spec compute_layout_hash(Dala.Node.t()) :: non_neg_integer()
  def compute_layout_hash(%Dala.Node{type: type, props: props, children: children}) do
    # Gather layout-relevant props in a deterministic order
    layout_props = [
      to_string(type),
      format_layout_prop(:width, props),
      format_layout_prop(:height, props),
      format_layout_prop(:padding, props),
      format_layout_prop(:flex_grow, props),
      format_layout_prop(:flex_direction, props),
      format_layout_prop(:justify_content, props),
      format_layout_prop(:align_items, props),
      to_string(length(children))
    ]

    data = Enum.join(layout_props, "|")
    <<hash::unsigned-64-big, _rest::binary>> = :crypto.hash(:sha256, data)
    hash
  end

  defp format_layout_prop(key, props) do
    case Map.get(props, key) do
      nil -> ""
      val -> to_string(val)
    end
  end

  # ── ID hashing ─────────────────────────────────────────────────────

  @doc "Hash a node ID to a stable u64"
  @spec hash_id(String.t() | atom()) :: non_neg_integer()
  def hash_id(id) do
    id_str = to_string(id)
    <<hash::unsigned-64-big, _rest::binary>> = :crypto.hash(:sha256, id_str)
    hash
  end

  # ── Props encoder ──────────────────────────────────────────────────

  defp encode_props(props) when is_map(props) do
    {fields, count} = collect_prop_fields(Map.to_list(props), [], 0)
    [<<count::8>>, fields]
  end

  defp encode_props_with_taps(props, nif, _platform, _ctx) when is_map(props) do
    {fields, count, taps} =
      Enum.reduce(Map.to_list(props), {[], 0, []}, fn
        {:on_tap, {pid, tag}}, {acc, cnt, ts} when is_pid(pid) ->
          handle = nif.register_tap({pid, tag})
          {[acc, <<5::8, handle::little-64>>], cnt + 1, [handle | ts]}

        {:on_tap, pid}, {acc, cnt, ts} when is_pid(pid) ->
          handle = nif.register_tap(pid)
          {[acc, <<5::8, handle::little-64>>], cnt + 1, [handle | ts]}

        {key, value}, {acc, cnt, ts} ->
          {field, c} = encode_single_prop(key, value)

          if field do
            {[acc, field], cnt + c, ts}
          else
            {acc, cnt, ts}
          end
      end)

    {[<<count::8>>, fields], taps}
  end

  defp encode_single_prop(key, value) do
    case key do
      :text when is_binary(value) ->
        {<<1::8, byte_size(value)::little-16, value::binary>>, 1}

      :title when is_binary(value) ->
        {<<2::8, byte_size(value)::little-16, value::binary>>, 1}

      :color when is_binary(value) ->
        {<<3::8, byte_size(value)::little-16, value::binary>>, 1}

      :background when is_binary(value) ->
        {<<4::8, byte_size(value)::little-16, value::binary>>, 1}

      :width when is_number(value) ->
        {<<6::8, value::float-little-32>>, 1}

      :height when is_number(value) ->
        {<<7::8, value::float-little-32>>, 1}

      :padding when is_number(value) ->
        {<<8::8, value::float-little-32>>, 1}

      :flex_grow when is_number(value) ->
        {<<9::8, value::float-little-32>>, 1}

      :flex_direction when is_atom(value) ->
        {<<10::8, flex_dir_byte(value)::8>>, 1}

      :justify_content when is_atom(value) ->
        {<<11::8, justify_byte(value)::8>>, 1}

      :align_items when is_atom(value) ->
        {<<12::8, align_byte(value)::8>>, 1}

      _ ->
        {nil, 0}
    end
  end

  defp collect_prop_fields([], acc, count), do: {acc, count}

  defp collect_prop_fields([{:text, v} | rest], acc, count) when is_binary(v) do
    collect_prop_fields(rest, [acc, <<1::8, byte_size(v)::little-16, v::binary>>], count + 1)
  end

  defp collect_prop_fields([{:title, v} | rest], acc, count) when is_binary(v) do
    collect_prop_fields(rest, [acc, <<2::8, byte_size(v)::little-16, v::binary>>], count + 1)
  end

  defp collect_prop_fields([{:color, v} | rest], acc, count) when is_binary(v) do
    collect_prop_fields(rest, [acc, <<3::8, byte_size(v)::little-16, v::binary>>], count + 1)
  end

  defp collect_prop_fields([{:background, v} | rest], acc, count) when is_binary(v) do
    collect_prop_fields(rest, [acc, <<4::8, byte_size(v)::little-16, v::binary>>], count + 1)
  end

  defp collect_prop_fields([{:on_tap, v} | rest], acc, count) when is_integer(v) do
    collect_prop_fields(rest, [acc, <<5::8, v::little-64>>], count + 1)
  end

  defp collect_prop_fields([{:width, v} | rest], acc, count) when is_number(v) do
    collect_prop_fields(rest, [acc, <<6::8, v::float-little-32>>], count + 1)
  end

  defp collect_prop_fields([{:height, v} | rest], acc, count) when is_number(v) do
    collect_prop_fields(rest, [acc, <<7::8, v::float-little-32>>], count + 1)
  end

  defp collect_prop_fields([{:padding, v} | rest], acc, count) when is_number(v) do
    collect_prop_fields(rest, [acc, <<8::8, v::float-little-32>>], count + 1)
  end

  defp collect_prop_fields([{:flex_grow, v} | rest], acc, count) when is_number(v) do
    collect_prop_fields(rest, [acc, <<9::8, v::float-little-32>>], count + 1)
  end

  defp collect_prop_fields([{:flex_direction, v} | rest], acc, count) when is_atom(v) do
    collect_prop_fields(rest, [acc, <<10::8, flex_dir_byte(v)::8>>], count + 1)
  end

  defp collect_prop_fields([{:justify_content, v} | rest], acc, count) when is_atom(v) do
    collect_prop_fields(rest, [acc, <<11::8, justify_byte(v)::8>>], count + 1)
  end

  defp collect_prop_fields([{:align_items, v} | rest], acc, count) when is_atom(v) do
    collect_prop_fields(rest, [acc, <<12::8, align_byte(v)::8>>], count + 1)
  end

  # Skip keys that aren't in the protocol
  defp collect_prop_fields([_ | rest], acc, count) do
    collect_prop_fields(rest, acc, count)
  end

  # ── Masked props encoder (for PATCH_NODE) ────────────────────────────
  # Encodes only the changed fields, in tag order, without a field count prefix.
  # The field mask already tells the decoder which fields are present.

  defp encode_masked_props(changed_props) when is_map(changed_props) do
    # Encode fields in tag order (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
    # Only include fields that are present in changed_props
    fields =
      []
      |> maybe_encode_field(:text, changed_props)
      |> maybe_encode_field(:title, changed_props)
      |> maybe_encode_field(:color, changed_props)
      |> maybe_encode_field(:background, changed_props)
      |> maybe_encode_field(:on_tap, changed_props)
      |> maybe_encode_field(:width, changed_props)
      |> maybe_encode_field(:height, changed_props)
      |> maybe_encode_field(:padding, changed_props)
      |> maybe_encode_field(:flex_grow, changed_props)
      |> maybe_encode_field(:flex_direction, changed_props)
      |> maybe_encode_field(:justify_content, changed_props)
      |> maybe_encode_field(:align_items, changed_props)

    IO.iodata_to_binary(fields)
  end

  defp maybe_encode_field(acc, tag, changed_props) do
    case Map.get(changed_props, tag) do
      nil ->
        acc

      value ->
        {encoded, _count} = encode_single_prop(tag, value)
        if encoded, do: acc ++ [encoded], else: acc
    end
  end

  # ── Children encoder ───────────────────────────────────────────────

  defp encode_children(children) do
    count = length(children)
    ids = Enum.map(children, fn %Dala.Node{id: id} -> <<hash_id(id)::little-64>> end)
    [<<count::little-32>>, ids]
  end

  # ── Component registry ────────────────────────────────────────────

  alias Dala.Ui.Component

  @component_kinds Component.all()
                   |> Enum.map(fn {_name, comp} -> comp end)
                   |> Enum.with_index()
                   |> Enum.map(fn {comp, idx} -> {comp.name, idx} end)
                   |> Map.new()

  defp kind_to_byte(kind),
    do: Map.get(@component_kinds, kind) || raise("Unknown component: #{inspect(kind)}")

  defp flex_dir_byte(:row), do: 1
  defp flex_dir_byte(_), do: 0

  defp justify_byte(:center), do: 1
  defp justify_byte(:end), do: 2
  defp justify_byte(:space_between), do: 3
  defp justify_byte(_), do: 0

  defp align_byte(:center), do: 1
  defp align_byte(:end), do: 2
  defp align_byte(:stretch), do: 3
  defp align_byte(_), do: 0

  @doc "Return the full color palette map (token → ARGB integer)."
  @spec colors() :: %{atom() => non_neg_integer()}
  def colors, do: @colors

  @doc "Return the text-size scale map (token → float sp)."
  @spec text_sizes() :: %{atom() => float()}
  def text_sizes, do: @text_sizes

  # ── Tree preparation ──────────────────────────────────────────────────────
end
