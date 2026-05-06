defmodule Dala.Spark.Transformers.Render do
  @moduledoc """
  Spark transformer that generates the `render/1` function from DSL entities.

  Walks the entity tree (screen → container children → leaves) and produces
  a `render/1` that builds the same node maps `Dala.UI` functions return:

      %{type: :column, props: %{...}, children: [...]}

  Container entities (`column`, `row`, `box`, `scroll`, `modal`, `pressable`,
  `safe_area`) carry a `:children` field populated by Spark's `recursive_as`
  mechanism. Leaf entities have no children.
  """

  use Spark.Dsl.Transformer

  # Regex compiled at runtime to avoid OTP 28 compile-time literal issue
  # (AGENTS.md rule #9).
  @at_ref_regex Regex.compile!("@([a-zA-Z_]\\w*)")

  @impl true
  def transform(dsl_state) do
    case Spark.Dsl.Transformer.get_entities(dsl_state, [:screen]) do
      [] ->
        {:ok, dsl_state}

      screen_entities ->
        # Build render tree from all top-level entities in the screen section
        render_ast = build_children_ast(screen_entities)

        render_fn =
          quote do
            def render(assigns) do
              unquote(render_ast)
            end
          end

        {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], render_fn)}
    end
  end

  # ── AST builders ──────────────────────────────────────────────────────────

  # Build a list of child ASTs. When there's a single child, unwrap to avoid
  # wrapping everything in an extra list.
  defp build_children_ast([]) do
    quote do: []
  end

  defp build_children_ast([single]) do
    quote do: [unquote(build_node_ast(single))]
  end

  defp build_children_ast(entities) when is_list(entities) do
    nodes = Enum.map(entities, &build_node_ast/1)
    quote do: unquote(nodes)
  end

  # Build AST for a single entity → %{type: atom, props: map, children: list}
  defp build_node_ast(entity) do
    type = struct_to_type(entity.__struct__)
    props_ast = build_props_ast(entity)
    children = Map.get(entity, :children, [])
    children_ast = build_children_ast(children)

    quote do
      %{type: unquote(type), props: unquote(props_ast), children: unquote(children_ast)}
    end
  end

  # ── Type mapping ──────────────────────────────────────────────────────────

  # Maps DSL struct modules to the :type atom that Dala.UI uses.
  # Must stay in sync with Dala.UI function → type mappings.
  defp struct_to_type(Dala.Spark.Dsl.Text), do: :text
  defp struct_to_type(Dala.Spark.Dsl.Button), do: :button
  defp struct_to_type(Dala.Spark.Dsl.Icon), do: :icon
  defp struct_to_type(Dala.Spark.Dsl.Divider), do: :divider
  defp struct_to_type(Dala.Spark.Dsl.Spacer), do: :spacer
  defp struct_to_type(Dala.Spark.Dsl.TextField), do: :text_field
  defp struct_to_type(Dala.Spark.Dsl.Toggle), do: :toggle
  defp struct_to_type(Dala.Spark.Dsl.Slider), do: :slider
  defp struct_to_type(Dala.Spark.Dsl.Switch), do: :switch
  defp struct_to_type(Dala.Spark.Dsl.Image), do: :image
  defp struct_to_type(Dala.Spark.Dsl.Video), do: :video
  defp struct_to_type(Dala.Spark.Dsl.ActivityIndicator), do: :activity_indicator
  defp struct_to_type(Dala.Spark.Dsl.ProgressBar), do: :progress_bar
  defp struct_to_type(Dala.Spark.Dsl.StatusBar), do: :status_bar
  defp struct_to_type(Dala.Spark.Dsl.RefreshControl), do: :refresh_control
  defp struct_to_type(Dala.Spark.Dsl.WebView), do: :web_view
  defp struct_to_type(Dala.Spark.Dsl.CameraPreview), do: :camera_preview
  defp struct_to_type(Dala.Spark.Dsl.NativeView), do: :native_view
  defp struct_to_type(Dala.Spark.Dsl.TabBar), do: :tab_bar
  defp struct_to_type(Dala.Spark.Dsl.DalaList), do: :list
  defp struct_to_type(Dala.Spark.Dsl.Column), do: :column
  defp struct_to_type(Dala.Spark.Dsl.Row), do: :row
  defp struct_to_type(Dala.Spark.Dsl.Box), do: :box
  defp struct_to_type(Dala.Spark.Dsl.Scroll), do: :scroll
  defp struct_to_type(Dala.Spark.Dsl.Modal), do: :modal
  defp struct_to_type(Dala.Spark.Dsl.Pressable), do: :pressable
  defp struct_to_type(Dala.Spark.Dsl.SafeArea), do: :safe_area

  # ── Props building ────────────────────────────────────────────────────────

  # Build a map AST with only non-nil props. @ref strings are converted to
  # interpolation expressions so they resolve at render time.
  defp build_props_ast(entity) do
    struct_module = entity.__struct__

    fields =
      struct_module.__struct__()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.filter(&(&1 not in [:__spark_metadata__, :children]))

    pairs =
      fields
      |> Enum.filter(&(Map.get(entity, &1) != nil))
      |> Enum.map(fn field ->
        value = Map.get(entity, field)
        key = field
        val_ast = build_value_ast(value, key)
        {key, val_ast}
      end)

    # Build the map AST manually so @ref interpolations are preserved as code
    {:%{}, [], pairs}
  end

  # Build AST for a prop value. Strings with @ref patterns become
  # interpolation expressions; everything else is escaped as a literal.
  defp build_value_ast(value, _key) when is_binary(value) do
    case process_at_refs_in_string(value) do
      {:literal, literal} -> literal
      {:interpolated, ast} -> ast
    end
  end

  defp build_value_ast(value, _key) when is_list(value) do
    Enum.map(value, &build_value_ast(&1, nil))
  end

  defp build_value_ast(value, _key) when is_map(value) do
    pairs =
      Enum.map(value, fn {k, v} ->
        {build_value_ast(k, nil), build_value_ast(v, nil)}
      end)

    {:%{}, [], pairs}
  end

  defp build_value_ast(value, _key) do
    Macro.escape(value)
  end

  # ── @ref processing ───────────────────────────────────────────────────────
  #
  # "Count: @count" → {:interpolated, quote do: "Count: " <> to_string(assigns.count)}
  # "Hello"         → {:literal, "Hello"}
  #
  # We produce string-concatenation AST so the render function accesses
  # `assigns.key` at runtime. `to_string/1` handles non-string assigns.

  defp process_at_refs_in_string(string) do
    # Find all @ref positions
    matches =
      Regex.scan(@at_ref_regex, string, return: :index)
      |> Enum.map(fn [{start, len}, {key_start, key_len}] ->
        %{
          full_start: start,
          full_end: start + len,
          key_start: key_start,
          key_len: key_len
        }
      end)

    if matches == [] do
      {:literal, Macro.escape(string)}
    else
      # Build a concatenation of literal parts and assign accesses
      parts = build_interpolation_parts(string, matches)
      {:interpolated, parts}
    end
  end

  defp build_interpolation_parts(string, matches) do
    # Collect all the segments: literal text between refs, and ref accesses
    segments =
      matches
      |> Enum.reduce({0, []}, fn match, {offset, acc} ->
        # Literal text before this @ref
        literal_before = binary_part(string, offset, match.full_start - offset)

        # The assign key name
        key = binary_part(string, match.key_start, match.key_len)
        key_atom = String.to_atom(key)

        acc =
          acc
          |> maybe_add_literal(literal_before)
          |> Kernel.++([quote(do: to_string(assigns[unquote(key_atom)]))])

        {match.full_end, acc}
      end)
      |> then(fn {offset, acc} ->
        # Trailing literal text
        trailing = binary_part(string, offset, byte_size(string) - offset)
        maybe_add_literal(acc, trailing)
      end)

    # Combine segments with <>
    case segments do
      [single] -> single
      multiple -> combine_with_concat(multiple)
    end
  end

  defp maybe_add_literal(acc, ""), do: acc
  defp maybe_add_literal(acc, literal), do: acc ++ [literal]

  defp combine_with_concat([a, b | rest]) do
    base = quote(do: unquote(a) <> unquote(b))

    Enum.reduce(rest, base, fn part, acc ->
      quote(do: unquote(acc) <> unquote(part))
    end)
  end
end
