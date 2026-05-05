defmodule Dala.Spark.Transformers.Render do
  @moduledoc """
  Spark transformer that generates the `render/1` function for screens using
  the DSL with UI components.

  This transformer:
  1. Extracts UI component entities from the DSL
  2. Generates a render function that builds the component tree
  3. Handles all UI component types defined in Dala.UI
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Get the screen entity
    case Spark.Dsl.Transformer.get_entities(dsl_state, [:screen]) do
      [] ->
        {:ok, dsl_state}

      [screen_entity] ->
        # Build render tree from screen's children
        render_tree = build_render_tree(screen_entity.children)

        # Generate render/1 function
        render_fn = quote do
          def render(assigns) do
            unquote(render_tree)
          end
        end

        # Inject the generated code into the module
        {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], render_fn)}

      _ ->
        {:ok, dsl_state}
    end
  end

  # Build render tree from DSL entities
  defp build_render_tree(children) when is_list(children) do
    Enum.map(children, &build_node/1)
  end

  defp build_node(%Spark.Dsl.Entity{} = entity) do
    type = entity.__struct__
    props = build_props(entity)
    children = build_render_tree(Map.get(entity, :children, []))

    quote do
      %{
        type: unquote(type),
        props: unquote(Macro.escape(props)),
        children: unquote(children)
      }
    end
  end

  defp build_node(other), do: Macro.escape(other)

  defp build_props(entity) do
    # Get the struct module
    struct_module = entity.__struct__

    # Get the struct fields (excluding __spark_metadata__)
    fields = struct_module.__struct__()
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.filter(&(&1 != :__spark_metadata__))

    # Extract only the props that are set (not nil)
    Enum.reduce(fields, %{}, fn field, acc ->
      case Map.get(entity, field) do
        nil -> acc
        value -> Map.put(acc, field, process_at_refs(value))
      end
    end)
  end

  @doc """
  Process a string value, replacing @ref with assigns.access.

  Example: "Count: @count" becomes: "Count: " <> assigns.count
  """
  def process_at_refs(value) when is_binary(value) do
    Regex.replace(~r/@(\w+)/, value, fn _, key ->
      "\#{assigns.#{key}}"
    end)
  end

  def process_at_refs(value), do: value
end
