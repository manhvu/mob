defmodule Dala.Node do
  @moduledoc """
  Structured representation of a UI node in the Dala framework.

  Using a struct instead of raw maps provides:
  - Compile-time verification of field names
  - Default values for optional fields
  - Clear documentation of the node structure

  ## Fields

    * `:id` — Stable identity for diffing (required for proper reconciliation)
    * `:type` — Atom indicating the component type (`:text`, `:button`, `:column`, etc.)
    * `:props` — Map of component-specific properties
    * `:children` — List of child `Dala.Node` structs

  ## Example

      %Dala.Node{
        id: "root",
        type: :column,
        props: %{padding: :md},
        children: [
          %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}},
          %Dala.Node{id: "b1", type: :button, props: %{title: "Click"}}
        ]
      }
  """

  @type t :: %__MODULE__{
          id: String.t() | atom(),
          type: atom(),
          props: map(),
          children: [t()]
        }

  defstruct [
    :id,
    :type,
    props: %{},
    children: []
  ]

  @doc """
  Create a new Node struct from a map.

  Converts the map representation (used by Dala.UI functions) to a proper Node struct.
  Generates an ID if not present.

  ## Example

      Dala.Node.from_map(%{
        type: :text,
        props: %{text: "Hello"},
        children: []
      }, "parent:0")

  """
  @spec from_map(map(), String.t()) :: t()
  def from_map(%{type: type} = map, default_id) do
    id = map[:id] || Map.get(map, :props, %{})[:id] || default_id

    children =
      Map.get(map, :children, [])
      |> Enum.with_index()
      |> Enum.map(fn {child, idx} ->
        Dala.Node.from_map(child, "#{id}:#{idx}")
      end)

    %__MODULE__{
      id: id,
      type: type,
      props: Map.get(map, :props, %{}),
      children: children
    }
  end

  @doc """
  Convert a Node struct back to a map representation.

  This is used before sending to the renderer/native side.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{id: id, type: type, props: props, children: children}) do
    %{
      type: type,
      props: Map.put(props, :id, id),
      children: Enum.map(children, &to_map/1)
    }
  end
end
