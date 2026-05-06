defmodule Dala.Renderer do
  @moduledoc """
  Serializes a component tree to JSON and passes it to the platform NIF in
  a single call. Compose (Android) and SwiftUI (iOS) handle diffing and
  rendering internally.

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

  A `%Dala.Style{}` value under the `:style` key is merged into the node's
  own props before serialisation. Inline props override style values.

  ## Platform blocks

  Props scoped to one platform are silently ignored on the other:

      props: %{padding: 12, ios: %{padding: 20}}
      # iOS sees padding: 20; Android sees padding: 12

  ## Injecting a mock NIF

      Dala.Renderer.render(tree, :android, MockNIF)
  """

  alias Dala.{Style, Theme}

  @default_nif :dala_nif

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

  # Props whose atom values are resolved as colors
  @color_props ~w(background text_color border_color color placeholder_color)a
  # Props whose atom values are resolved as spacing or radius tokens
  @spacing_props ~w(padding padding_top padding_right padding_bottom padding_left gap)a
  @radius_props ~w(corner_radius)a
  # Props whose atom values are resolved as text sizes (scaled by type_scale)
  @size_props ~w(text_size font_size)a

  # ── Component defaults ────────────────────────────────────────────────────
  # Injected for missing styling props. Use semantic tokens so they inherit
  # the active theme automatically. Explicit props always win.

  @component_defaults %{
    button: %{
      background: :primary,
      text_color: :on_primary,
      padding: :space_md,
      corner_radius: :radius_md,
      text_size: :base,
      font_weight: "medium",
      fill_width: true,
      text_align: :center
    },
    text_field: %{
      background: :surface_raised,
      text_color: :on_surface,
      placeholder_color: :muted,
      border_color: :border,
      padding: :space_sm,
      corner_radius: :radius_sm,
      text_size: :base
    },
    divider: %{
      color: :border
    },
    progress: %{
      color: :primary
    },
    image: %{
      resize_mode: :cover
    },
    switch: %{
      value: false,
      track_color: :primary
    },
    activity_indicator: %{
      size: :small,
      animating: true,
      color: :primary
    },
    modal: %{
      visible: false,
      presentation_style: :full_screen
    },
    refresh_control: %{
      refreshing: false
    },
    scroll: %{
      horizontal: false
    },
    pressable: %{},
    safe_area: %{},
    status_bar: %{
      bar_style: :default,
      hidden: false
    },
    progress_bar: %{
      progress: 0.0,
      indeterminate: false,
      color: :primary
    },
    list: %{
      scroll: true
    }
  }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Render a component tree for the given platform.

  Loads the active `Dala.Theme`, clears the tap registry, serialises the tree
  to JSON, and calls `set_root/1` on the NIF. Returns `{:ok, :json_tree}`.

  `transition` is an atom (`:push`, `:pop`, `:reset`, `:none`) for the nav
  animation. Defaults to `:none` (instant swap).
  """
  @spec render(map(), atom(), module() | atom(), atom()) :: {:ok, :json_tree} | {:error, term()}
  def render(tree, platform, nif \\ @default_nif, _transition \\ :none) do
    theme = Theme.current()

    ctx = %{
      colors: Theme.color_map(theme),
      spacing: Theme.spacing_map(theme),
      radii: Theme.radius_map(theme),
      type_scale: theme.type_scale
    }

    nif.clear_taps()

    json =
      tree
      |> prepare(nif, platform, ctx)
      |> :json.encode()
      |> IO.iodata_to_binary()

    nif.set_root(json)
    {:ok, :json_tree}
  end

  # Optimized version that batches tap registrations
  @spec render_fast(Dala.Screen.t(), atom(), module(), atom()) :: {:ok, :json_tree}
  def render_fast(tree, platform, nif \\ @default_nif, transition \\ :none) do
    theme = Theme.current()

    ctx = %{
      colors: Theme.color_map(theme),
      spacing: Theme.spacing_map(theme),
      radii: Theme.radius_map(theme),
      type_scale: theme.type_scale
    }

    nif.clear_taps()
    nif.set_transition(transition)

    {prepared, taps} = prepare_with_taps(tree, nif, platform, ctx)

    # Batch register taps (avoids clear_taps + individual register_tap)
    nif.set_taps(taps)

    json =
      prepared
      |> :json.encode()
      |> IO.iodata_to_binary()

    nif.set_root(json)
    {:ok, :json_tree}
  end

  @doc """
  Render using incremental patches instead of full tree.

  Compares `old_tree` with `new_tree`, computes the diff, and sends
  only the patches to native. Falls back to full render on first call
  (when `old_tree` is nil).

  `new_tree` can be either a map (from Dala.UI functions) or a `Dala.Node` struct.
  If it's a map, it will be converted to a `Dala.Node` first.

  Returns `{:ok, patches}` where patches is the list of patch tuples.
  """
  @spec render_patches(
          Dala.Node.t() | map() | nil,
          Dala.Node.t() | map(),
          atom(),
          module(),
          atom()
        ) :: {:ok, [Dala.Diff.patch()]}
  def render_patches(old_tree, new_tree, platform, nif \\ @default_nif, transition \\ :none) do
    theme = Theme.current()

    ctx = %{
      colors: Theme.color_map(theme),
      spacing: Theme.spacing_map(theme),
      radii: Theme.radius_map(theme),
      type_scale: theme.type_scale
    }

    # Convert to Node structs if needed
    old_node = to_node(old_tree, "root")
    new_node = to_node(new_tree, "root")

    # Compute diff
    patches = Dala.Diff.diff(old_node, new_node)

    if patches == [] do
      # Nothing changed
      {:ok, []}
    else
      # Check if we have a full replacement (first render or root change)
      has_replace? = Enum.any?(patches, fn {action, _} -> action == :replace end)

      if has_replace? do
        # Full render for replacements
        nif.clear_taps()
        nif.set_transition(transition)

        prepared = prepare(new_node, nif, platform, ctx)
        {taps, prepared} = extract_taps(prepared)
        nif.set_taps(taps)

        json =
          prepared
          |> :json.encode()
          |> IO.iodata_to_binary()

        nif.set_root(json)
        {:ok, patches}
      else
        # Send incremental patches
        send_patches(patches, new_node, platform, nif, ctx)
        {:ok, patches}
      end
    end
  end

  defp to_node(nil, _), do: nil
  defp to_node(%Dala.Node{} = node, _), do: node
  defp to_node(map, default_id), do: Dala.Node.from_map(map, default_id)

  defp extract_taps(node) do
    # Extract tap handles from prepared node
    # This is a simplified version - in reality, taps are registered during prepare
    {[], node}
  end

  # Send patches to native
  defp send_patches(patches, _tree, _platform, nif, _ctx) do
    binary = encode_frame(patches)

    if function_exported?(nif, :apply_patches, 1) do
      nif.apply_patches(binary)
    else
      IO.puts("[Dala] apply_patches not available, got patches: #{inspect(patches)}")
    end
  end

  # ── Binary protocol v2 encoder ──────────────────────────────────────
  #
  # Header:  [u16 version=1][u16 patch_count]
  # Opcodes:
  #   0x01 INSERT  [u64 id][u64 parent][u32 index][u8 type][PROPS]
  #   0x02 REMOVE  [u64 id]
  #   0x03 UPDATE  [u64 id][PROPS]
  #
  # PROPS:   [u8 field_count] repeat [u8 tag][value...]
  #   1=text[u16 len][bytes]  2=title[u16 len][bytes]  3=color[u16 len][bytes]
  #   4=background[u16 len][bytes]  5=on_tap[u64]
  #   6=width[f32]  7=height[f32]  8=padding[f32]  9=flex_grow[f32]
  #   10=flex_direction[u8]  11=justify_content[u8]  12=align_items[u8]

  @doc "Encode patches to binary frame format for the native side"
  def encode_frame(patches) when is_list(patches) do
    body = Enum.map(patches, &encode_patch/1)

    IO.iodata_to_binary([
      <<1::little-16, length(patches)::little-16>>,
      body
    ])
  end

  defp encode_patch({:insert, parent_id, index, %Dala.Node{} = node}) do
    id = hash_id(node.id)
    parent = hash_id(parent_id)

    [
      <<0x01, id::little-64, parent::little-64, index::little-32, kind_to_byte(node.type)::8>>,
      encode_props(node.props),
      encode_children(node.children)
    ]
  end

  defp encode_patch({:remove, id}) do
    <<0x02, hash_id(id)::little-64>>
  end

  defp encode_patch({:update_props, id, props}) do
    [<<0x03, hash_id(id)::little-64>>, encode_props(props)]
  end

  defp encode_patch({:replace, id, %Dala.Node{} = node}) do
    # Replace = remove old + insert new
    old_id = hash_id(id)
    new_id = hash_id(node.id)
    # Parent is unknown from replace alone; use 0 as sentinel (root)
    [
      <<0x02, old_id::little-64>>,
      <<0x01, new_id::little-64, 0::little-64, 0::little-32, kind_to_byte(node.type)::8>>,
      encode_props(node.props),
      encode_children(node.children)
    ]
  end

  # ── ID hashing ─────────────────────────────────────────────────────

  defp hash_id(id) do
    id_str = to_string(id)
    lo = :erlang.phash2(id_str, 0xFFFFFFFF)
    hi = :erlang.phash2({id_str, :hi}, 0xFFFFFFFF)
    Bitwise.bor(Bitwise.bsl(hi, 32), lo)
  end

  # ── Props encoder ──────────────────────────────────────────────────

  defp encode_props(props) when is_map(props) do
    {fields, count} = collect_prop_fields(Map.to_list(props), [], 0)
    [<<count::8>>, fields]
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

  # ── Children encoder ───────────────────────────────────────────────

  defp encode_children(children) do
    count = length(children)
    ids = Enum.map(children, fn %Dala.Node{id: id} -> <<hash_id(id)::little-64>> end)
    [<<count::little-32>>, ids]
  end

  # ── Enum byte helpers ──────────────────────────────────────────────

  defp kind_to_byte(:column), do: 0
  defp kind_to_byte(:row), do: 1
  defp kind_to_byte(:text), do: 2
  defp kind_to_byte(:button), do: 3
  defp kind_to_byte(:image), do: 4
  defp kind_to_byte(:scroll), do: 5
  defp kind_to_byte(:webview), do: 6
  defp kind_to_byte(_), do: 0

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

  defp patch_to_json({:move, id, parent_id, new_index}) do
    %{
      "action" => "move",
      "id" => to_string(id),
      "parent_id" => to_string(parent_id),
      "index" => new_index
    }
  end

  @doc "Return the full color palette map (token → ARGB integer)."
  @spec colors() :: %{atom() => non_neg_integer()}
  def colors, do: @colors

  @doc "Return the text-size scale map (token → float sp)."
  @spec text_sizes() :: %{atom() => float()}
  def text_sizes, do: @text_sizes

  # ── Tree preparation ──────────────────────────────────────────────────────

  defp prepare(%{type: type, props: props, children: children}, nif, platform, ctx) do
    defaults = Map.get(@component_defaults, type, %{})
    with_defaults = Map.merge(defaults, props)

    %{
      "type" => Atom.to_string(type),
      "props" => prepare_props(with_defaults, nif, platform, ctx),
      "children" => Enum.map(children, &prepare(&1, nif, platform, ctx))
    }
  end

  defp prepare_props(props, nif, platform, ctx) do
    # 1. Merge any %Dala.Style{} under the :style key (inline props win)
    {style, base} = Map.pop(props, :style)

    merged =
      case style do
        %Style{props: sp} -> Map.merge(sp, base)
        nil -> base
      end

    # 2. Resolve platform blocks (:ios / :android)
    ios_extras = Map.get(merged, :ios, %{})
    android_extras = Map.get(merged, :android, %{})
    platform_extra = if platform == :ios, do: ios_extras, else: android_extras

    final =
      merged
      |> Map.delete(:ios)
      |> Map.delete(:android)
      |> Map.merge(platform_extra)

    # 3. Serialize: convert atom keys, register taps/changes, resolve tokens.
    # on_tap with a tagged tuple also emits "accessibility_id" so test tooling
    # can locate elements by tag name without relying on screen coordinates.
    final
    |> Enum.flat_map(fn
      {:on_tap, pid} when is_pid(pid) ->
        [{"on_tap", nif.register_tap(pid)}]

      {:on_tap, {pid, tag}} when is_pid(pid) and is_atom(tag) ->
        [{"on_tap", nif.register_tap({pid, tag})}, {"accessibility_id", Atom.to_string(tag)}]

      {:on_tap, {pid, tag}} when is_pid(pid) ->
        [{"on_tap", nif.register_tap({pid, tag})}]

      {:on_change, {pid, tag}} when is_pid(pid) ->
        [{"on_change", nif.register_tap({pid, tag})}]

      {:on_focus, {pid, tag}} when is_pid(pid) ->
        [{"on_focus", nif.register_tap({pid, tag})}]

      {:on_blur, {pid, tag}} when is_pid(pid) ->
        [{"on_blur", nif.register_tap({pid, tag})}]

      {:on_submit, {pid, tag}} when is_pid(pid) ->
        [{"on_submit", nif.register_tap({pid, tag})}]

      # IME composition — fires for languages with multi-stage input (CJK,
      # Korean, Vietnamese, accent input). Phase atom is :began | :updating
      # | :committed | :cancelled. Apps that need commit-only behaviour
      # combine on_change + on_compose: ignore on_change while a composition
      # is active, replace text on :committed.
      {:on_compose, {pid, tag}} when is_pid(pid) ->
        [{"on_compose", nif.register_tap({pid, tag})}]

      {:on_end_reached, {pid, tag}} when is_pid(pid) ->
        [{"on_end_reached", nif.register_tap({pid, tag})}]

      {:on_tab_select, {pid, tag}} when is_pid(pid) ->
        [{"on_tab_select", nif.register_tap({pid, tag})}]

      # Generic selection event — used by pickers, menus, segmented controls.
      # Lists use a structured tag (see Dala.List) and emit on_tap; this is for
      # widgets where "selection" is the only meaningful interaction.
      {:on_select, {pid, tag}} when is_pid(pid) ->
        [{"on_select", nif.register_tap({pid, tag})}]

      # Each maps to a UIGestureRecognizer (iOS) / GestureDetector (Android).
      # The native side fires the registered handle when the gesture ends in
      # the recognized state. Per-widget opt-in — most widgets don't carry
      # gesture overhead by default.

      {:on_long_press, {pid, tag}} when is_pid(pid) ->
        [{"on_long_press", nif.register_tap({pid, tag})}]

      {:on_double_tap, {pid, tag}} when is_pid(pid) ->
        [{"on_double_tap", nif.register_tap({pid, tag})}]

      {:on_swipe, {pid, tag}} when is_pid(pid) ->
        [{"on_swipe", nif.register_tap({pid, tag})}]

      {:on_swipe_left, {pid, tag}} when is_pid(pid) ->
        [{"on_swipe_left", nif.register_tap({pid, tag})}]

      {:on_swipe_right, {pid, tag}} when is_pid(pid) ->
        [{"on_swipe_right", nif.register_tap({pid, tag})}]

      {:on_swipe_up, {pid, tag}} when is_pid(pid) ->
        [{"on_swipe_up", nif.register_tap({pid, tag})}]

      {:on_swipe_down, {pid, tag}} when is_pid(pid) ->
        [{"on_swipe_down", nif.register_tap({pid, tag})}]

      # ── Batch 5: high-frequency events ────────────────────────────────────
      # `on_scroll` is the prototype: native side throttles + delta-thresholds
      # before any enif_send. Default is 30 Hz / 1 px (see Dala.Event.Throttle).
      # Forms accepted:
      #   on_scroll: {pid, tag}                     # default throttle
      #   on_scroll: {pid, tag, throttle: 100}      # 10 Hz
      #   on_scroll: {pid, tag, debounce: 200}      # only after stillness
      #   on_scroll: {pid, tag, throttle: 0}        # raw (escape hatch)
      # The throttle config is serialised as a sibling prop "scroll_config"
      # which the native side reads alongside the registered handle.

      {:on_scroll, {pid, tag}} when is_pid(pid) ->
        [{"on_scroll", nif.register_tap({pid, tag})}]

      {:on_scroll, {pid, tag, opts}} when is_pid(pid) and is_list(opts) ->
        cfg = Dala.Event.Throttle.parse(:scroll, opts)
        [{"on_scroll", nif.register_tap({pid, tag})}, {"scroll_config", encode_throttle(cfg)}]

      {:on_drag, {pid, tag}} when is_pid(pid) ->
        [{"on_drag", nif.register_tap({pid, tag})}]

      {:on_drag, {pid, tag, opts}} when is_pid(pid) and is_list(opts) ->
        cfg = Dala.Event.Throttle.parse(:drag, opts)
        [{"on_drag", nif.register_tap({pid, tag})}, {"drag_config", encode_throttle(cfg)}]

      {:on_pinch, {pid, tag}} when is_pid(pid) ->
        [{"on_pinch", nif.register_tap({pid, tag})}]

      {:on_pinch, {pid, tag, opts}} when is_pid(pid) and is_list(opts) ->
        cfg = Dala.Event.Throttle.parse(:pinch, opts)
        [{"on_pinch", nif.register_tap({pid, tag})}, {"pinch_config", encode_throttle(cfg)}]

      {:on_rotate, {pid, tag}} when is_pid(pid) ->
        [{"on_rotate", nif.register_tap({pid, tag})}]

      {:on_rotate, {pid, tag, opts}} when is_pid(pid) and is_list(opts) ->
        cfg = Dala.Event.Throttle.parse(:rotate, opts)
        [{"on_rotate", nif.register_tap({pid, tag})}, {"rotate_config", encode_throttle(cfg)}]

      {:on_pointer_move, {pid, tag}} when is_pid(pid) ->
        [{"on_pointer_move", nif.register_tap({pid, tag})}]

      {:on_pointer_move, {pid, tag, opts}} when is_pid(pid) and is_list(opts) ->
        cfg = Dala.Event.Throttle.parse(:pointer_move, opts)

        [
          {"on_pointer_move", nif.register_tap({pid, tag})},
          {"pointer_config", encode_throttle(cfg)}
        ]

      # ── Batch 5 Tier 2: semantic scroll events (single-fire, no payload) ──
      {:on_scroll_began, {pid, tag}} when is_pid(pid) ->
        [{"on_scroll_began", nif.register_tap({pid, tag})}]

      {:on_scroll_ended, {pid, tag}} when is_pid(pid) ->
        [{"on_scroll_ended", nif.register_tap({pid, tag})}]

      {:on_scroll_settled, {pid, tag}} when is_pid(pid) ->
        [{"on_scroll_settled", nif.register_tap({pid, tag})}]

      {:on_top_reached, {pid, tag}} when is_pid(pid) ->
        [{"on_top_reached", nif.register_tap({pid, tag})}]

      # `on_scrolled_past` requires a threshold; native side fires once when
      # scroll y crosses the boundary (latched: re-emits only after going back
      # below and past again).
      {:on_scrolled_past, {pid, tag, threshold}} when is_pid(pid) and is_number(threshold) ->
        [
          {"on_scrolled_past", nif.register_tap({pid, tag})},
          {"scrolled_past_threshold", threshold}
        ]

      # ── Batch 5 Tier 3: native-side scroll-driven UI primitives ───────────
      # These never round-trip to BEAM during scroll. Native side wires them
      # directly. Pass-through for the renderer; consumed by the platform
      # layer (SwiftUI .scrollPosition observer / Compose snapshotFlow).
      {:parallax, %{} = config} ->
        [{"parallax", encode_native_config(config)}]

      {:fade_on_scroll, %{} = config} ->
        [{"fade_on_scroll", encode_native_config(config)}]

      {:sticky_when_scrolled_past, %{} = config} ->
        [{"sticky_when_scrolled_past", encode_native_config(config)}]

      {key, value} ->
        [{Atom.to_string(key), resolve_token(key, value, ctx)}]
    end)
    |> Map.new()
  end

  # ── Token resolution ──────────────────────────────────────────────────────

  # Color props — two-step: theme semantic map → base palette
  defp resolve_token(key, value, ctx) when is_atom(value) and key in @color_props do
    resolve_color(value, ctx.colors)
  end

  # Text size props — scale table value by type_scale
  defp resolve_token(key, value, ctx) when is_atom(value) and key in @size_props do
    case Map.get(@text_sizes, value) do
      nil -> value
      size -> size * ctx.type_scale
    end
  end

  # Spacing props — spacing tokens first, then radius tokens, then pass through
  defp resolve_token(key, value, ctx) when key in @spacing_props do
    cond do
      is_atom(value) ->
        case Map.get(ctx.spacing, value) do
          nil -> value
          v -> v
        end

      true ->
        value
    end
  end

  # Radius props — radius tokens from theme
  defp resolve_token(key, value, ctx) when is_atom(value) and key in @radius_props do
    Map.get(ctx.radii, value, value)
  end

  defp resolve_token(_key, value, _ctx), do: value

  # Two-step color resolution:
  # 1. Check theme semantic map  (:primary → :blue_500)
  # 2. Check base palette        (:blue_500 → 0xFF2196F3)
  # 3. Pass through              (unknown atoms serialise as strings)
  defp resolve_color(value, theme_colors) when is_atom(value) do
    case Map.get(theme_colors, value) do
      nil ->
        Map.get(@colors, value, value)

      palette_atom when is_atom(palette_atom) ->
        Map.get(@colors, palette_atom, palette_atom)

      raw_int when is_integer(raw_int) ->
        raw_int
    end
  end

  defp resolve_color(value, _theme_colors), do: value

  # ── Batch 5 helpers ─────────────────────────────────────────────────────
  # Encode a Dala.Event.Throttle config for the native side. We use string
  # keys + plain numeric/boolean values so the JSON serialiser sends a flat
  # map across the NIF boundary. Native side reads these and stores per-handle.

  defp encode_throttle(%{} = cfg) do
    %{
      "throttle_ms" => cfg.throttle_ms,
      "debounce_ms" => cfg.debounce_ms,
      "delta_threshold" => cfg.delta_threshold,
      "leading" => cfg.leading,
      "trailing" => cfg.trailing
    }
  end

  # Encode a Tier-3 native-side scroll-driven config (parallax, fade_on_scroll,
  # sticky_when_scrolled_past). Atoms are stringified; nested structures
  # passed through as-is for native consumption.
  defp encode_native_config(%{} = config) do
    Map.new(config, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), encode_native_value(v)}
      {k, v} -> {k, encode_native_value(v)}
    end)
  end

  defp encode_native_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: Atom.to_string(v)

  defp encode_native_value(v), do: v

  # ── Optimized tree preparation with tap batching ──────────────────────

  defp prepare_with_taps(%{type: type, props: props, children: children}, nif, platform, ctx) do
    defaults = Map.get(@component_defaults, type, %{})
    with_defaults = Map.merge(defaults, props)

    {prepared_children, all_taps} =
      children
      |> Enum.map(&prepare_with_taps(&1, nif, platform, ctx))
      |> Enum.unzip()

    {prepared_props, prop_taps} = prepare_props_with_taps(with_defaults, nif, platform, ctx)

    node = %{
      "type" => Atom.to_string(type),
      "props" => prepared_props,
      "children" => prepared_children
    }

    taps = List.flatten([prop_taps | all_taps])
    {node, taps}
  end

  defp prepare_props_with_taps(props, nif, platform, ctx) do
    {style, base} = Map.pop(props, :style)

    merged =
      case style do
        %Dala.Style{props: sp} -> Map.merge(sp, base)
        nil -> base
      end

    ios_extras = Map.get(merged, :ios, %{})
    android_extras = Map.get(merged, :android, %{})
    platform_extra = if platform == :ios, do: ios_extras, else: android_extras

    final =
      merged
      |> Map.delete(:ios)
      |> Map.delete(:android)
      |> Map.merge(platform_extra)

    {prepared, taps} =
      final
      |> Enum.reduce({%{}, []}, fn
        {key, value}, {acc, taps} when is_tuple(value) and tuple_size(value) >= 2 ->
          {pid, tag} = value

          if is_pid(pid) do
            handle = nif.register_tap({pid, tag})
            props = Map.put(acc, Atom.to_string(key), handle)

            props =
              if key == :on_tap,
                do: Map.put(props, "accessibility_id", Atom.to_string(tag)),
                else: props

            {props, [handle | taps]}
          else
            {Map.put(acc, Atom.to_string(key), resolve_token(key, value, ctx)), taps}
          end

        {key, value}, {acc, taps} ->
          {Map.put(acc, Atom.to_string(key), resolve_token(key, value, ctx)), taps}
      end)

    {prepared, taps}
  end
end
