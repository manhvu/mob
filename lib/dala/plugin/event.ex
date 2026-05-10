defmodule Dala.Plugin.Event do
  @moduledoc """
  Typed event definitions for Dala plugins.

  Provides a type-safe event system with compile-time field validation
  and efficient binary encoding for the native bridge.

  ## Defining Events

  Events are defined inside component blocks:

      component "chart" do
        event :zoom, %{x: :f32, y: :f32}
        event :pan, %{x: :f32, y: :f32}
      end

  This generates a struct module at `YourPlugin.Chart.Events.Zoom` with
  typed fields and validation.

  ## Event Struct

  The generated struct contains:
  - Fields declared in the event definition
  - `__event_name__/0` — returns the event atom
  - `__event_fields__/0` — returns list of field names
  - `__event_types__/0` — returns map of field name to type

  ## Encoding

  Events are encoded as binary for the native bridge using opcode 0xF2.
  """

  @type t :: %__MODULE__{
          name: atom(),
          fields: keyword(),
          module: module()
        }

  defstruct [:name, :fields, :module]

  @doc "Creates a new event definition."
  @spec new(atom(), keyword(), module()) :: t()
  def new(name, fields \\ [], module \\ nil) do
    %__MODULE__{
      name: name,
      fields: fields,
      module: module
    }
  end

  @doc "Returns the event name as a string."
  @spec name_string(t()) :: String.t()
  def name_string(%__MODULE__{name: name}), do: Atom.to_string(name)

  @doc "Returns the fully-qualified module name for an event struct."
  @spec event_module_name(atom(), module()) :: atom()
  def event_module_name(name, parent) do
    parent
    |> Module.concat(Events)
    |> Module.concat(Macro.camelize(Atom.to_string(name)))
  end

  @doc """
  Creates the AST for an event struct module definition.

  This is meant to be called at compile time inside a `__before_compile__` callback.
  """
  @spec expand(atom(), keyword() | map(), module()) :: Macro.t()
  def expand(name, fields, parent) when is_map(fields) do
    expand(name, Map.to_list(fields), parent)
  end

  def expand(name, fields, parent) do
    mod_name = event_module_name(name, parent)
    keys = Keyword.keys(fields)

    quote do
      defmodule unquote(mod_name) do
        @type t :: %__MODULE__{unquote_splicing(expand_fields(fields))}

        defstruct unquote(keys)

        @doc false
        def __event_name__, do: unquote(name)

        @doc false
        def __event_fields__, do: unquote(keys)

        @doc false
        def __event_types__, do: unquote(Macro.escape(Map.new(fields)))

        @doc false
        def validate(data) when is_map(data) do
          required = __event_fields__()
          missing = required -- Map.keys(data)

          if missing == [] do
            :ok
          else
            {:error, missing}
          end
        end

        defimpl Inspect do
          import Inspect.Algebra

          def inspect(struct, opts) do
            fields = unquote(keys)
            values = Enum.map(fields, fn k -> {k, Map.fetch!(struct, k)} end)
            concat(["#Dala.Event<", to_doc(values, opts), ">"])
          end
        end
      end
    end
  end

  defp expand_fields(fields) do
    Enum.map(fields, fn {key, type} ->
      quote do
        @type unquote(key) :: unquote(type)
      end
    end)
  end
end
