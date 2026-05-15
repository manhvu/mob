defmodule Dala.Plugin.Component do
  @moduledoc """
  Represents a single component schema within a plugin.

  Contains all metadata needed for code generation, validation, and runtime
  dispatch. This is the core of the schema-first architecture.
  """

  alias Dala.Plugin

  @type lifecycle_event :: :create | :update | :layout | :event | :dispose

  @type t :: %__MODULE__{
          name: Plugin.component_name(),
          plugin: Plugin.plugin_name(),
          props: [prop()],
          events: [event()],
          event_structs: %{atom() => module()},
          natives: %{String.t() => String.t()},
          capabilities: [Plugin.capability()],
          optional_capabilities: [atom()],
          lifecycle: [lifecycle_event()],
          doc: String.t() | nil,
          metadata: map()
        }

  @type prop :: %{
          name: Plugin.prop_name(),
          type: Plugin.prop_type(),
          required: boolean(),
          default: term(),
          doc: String.t() | nil
        }

  @type event :: %{
          name: Plugin.event_name(),
          payload: map(),
          doc: String.t() | nil
        }

  defstruct [
    :name,
    :plugin,
    props: [],
    events: [],
    event_structs: %{},
    natives: %{},
    capabilities: [],
    optional_capabilities: [],
    lifecycle: [:create, :update, :layout, :event, :dispose],
    doc: nil,
    metadata: %{}
  ]

  @doc """
  Adds a property to the component schema.

  Options:
    * `:required` — boolean, whether the prop is required (default: false)
    * `:default` — default value (default: nil)
    * `:doc` — documentation string (default: nil)
  """
  @spec add_prop(t(), Plugin.prop_name(), Plugin.prop_type(), keyword()) :: t()
  def add_prop(component, name, type, opts \\ []) do
    prop = %{
      name: name,
      type: type,
      required: Keyword.get(opts, :required, false),
      default: Keyword.get(opts, :default, nil),
      doc: Keyword.get(opts, :doc, nil)
    }

    %{component | props: component.props ++ [prop]}
  end

  @doc """
  Adds an event to the component schema.

  Options:
    * `:payload` — map of field names to types (default: %{})
    * `:doc` — documentation string (default: nil)
  """
  @spec add_event(t(), Plugin.event_name(), keyword()) :: t()
  def add_event(component, name, opts \\ []) do
    event = %{
      name: name,
      payload: Keyword.get(opts, :payload, %{}),
      doc: Keyword.get(opts, :doc, nil)
    }

    %{component | events: component.events ++ [event]}
  end

  @doc """
  Adds a native platform mapping to the component schema.

  `platform` is the platform string (e.g. `"ios"`, `"android"`).
  `class_name` is the native class name to instantiate.
  """
  @spec add_native(t(), String.t(), String.t()) :: t()
  def add_native(component, platform, class_name)
      when is_binary(platform) and is_binary(class_name) do
    %{component | natives: Map.put(component.natives, platform, class_name)}
  end

  @doc """
  Adds a required capability to the component schema.
  """
  @spec add_capability(t(), Plugin.capability()) :: t()
  def add_capability(component, capability) do
    %{component | capabilities: [capability | component.capabilities]}
  end

  @doc """
  Adds an optional capability to the component schema.

  Optional capabilities enhance the component but are not required for
  basic functionality.
  """
  @spec add_optional_capability(t(), atom()) :: t()
  def add_optional_capability(component, capability) do
    %{component | optional_capabilities: [capability | component.optional_capabilities]}
  end
end
