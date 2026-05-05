defmodule Dala.Spark.Transformers.GenerateMount do
  @moduledoc """
  Spark transformer that generates the `mount/3` function for screens using
  the DSL with @ref syntax.

  This transformer:
  1. Extracts attributes from the DSL
  2. Generates a mount function that initializes assigns with defaults
  3. Handles @ref references for shared state
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Get all attribute entities from the attributes section
    attributes = Spark.Dsl.Transformer.get_entities(dsl_state, [:attributes, :attribute])

    if Enum.any?(attributes) do
      # Build the mount function body with assign calls
      assign_calls =
        Enum.map(attributes, fn attr ->
          name = Map.get(attr, :name)
          default = Map.get(attr, :default)

          quote do
            socket = Dala.Socket.assign(socket, unquote(name), unquote(default))
          end
        end)

      # Generate the mount function
      mount_fn = quote do
        def mount(_params, _session, socket) do
          socket = unquote_splicing(assign_calls)
          {:ok, socket}
        end
      end

      # Inject the generated code into the module
      {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], mount_fn)}
    else
      {:ok, dsl_state}
    end
  end
end
