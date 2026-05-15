defmodule Dala.Plugin.ComponentDSL do
  @moduledoc """
  Evaluates the component definition DSL.

  Processes the `component "name" do ... end` block, building up the
  component schema with props, events, native mappings, and capabilities.
  """

  alias Dala.Plugin.Component

  @doc """
  Evaluates a component definition block.
  """
  @spec eval(module(), Dala.Plugin.Component.t(), Macro.t()) :: Dala.Plugin.Component.t()
  def eval(_plugin_module, component, block) do
    # Store component in process dictionary for the DSL to access
    key = {:__dala_component__, component.plugin}
    Process.put(key, component)

    try do
      # Execute the block - the DSL macros will modify the component
      # in the process dictionary
      Code.eval_quoted(block, [], __ENV__)

      # Retrieve the modified component
      Process.get(key)
    after
      # Clean up
      Process.delete(key)
    end
  end

  @doc """
  Defines a property for the component.

  ## Types

    * `:string` - UTF-8 string
    * `:bool` - boolean (true/false)
    * `:integer` - signed 64-bit integer
    * `:float` - 64-bit float
    * `:f32` - 32-bit float (binary protocol)
    * `:f64` - 64-bit float (binary protocol)
    * `:color` - color token or ARGB integer
    * `:binary` - binary data
    * `:list` - list of values
    * `:map` - map/dictionary

  ## Options

    * `:required` - if true, prop must be provided (default: false)
    * `:default` - default value if not provided
    * `:doc` - documentation string

  ## Example

      prop "volume", :f32, required: true
      prop "autoplay", :bool, default: false
      prop "source", :string
  """
  defmacro prop(name, type, opts \\ []) when is_binary(name) do
    quote do
      Dala.Plugin.ComponentDSL.add_prop(
        __MODULE__,
        unquote(name),
        unquote(type),
        unquote(opts)
      )
    end
  end

  @doc """
  Defines an event that the component can emit.

  ## Example

      event "progress"
      event "ended", payload: %{position: :f32, duration: :f32}
  """
  defmacro event(name, opts \\ []) when is_binary(name) do
    quote do
      Dala.Plugin.ComponentDSL.add_event(
        __MODULE__,
        unquote(name),
        unquote(opts)
      )
    end
  end

  @doc """
  Maps a component to a native platform class.

  ## Example

      native "ios", "DalaVideoView"
      native "android", "com.dala.video.VideoView"
  """
  defmacro native(platform, class_name)
           when is_binary(platform) and is_binary(class_name) do
    quote do
      Dala.Plugin.ComponentDSL.add_native(
        __MODULE__,
        unquote(platform),
        unquote(class_name)
      )
    end
  end

  @doc """
  Declares a capability that this component supports.

  Capabilities inform the runtime about special behaviors:

    * `:gestures` - handles pan/zoom/rotate gestures
    * `:accessibility` - provides accessibility tree
    * `:animation` - supports custom animations
    * `:textures` - renders to texture (e.g., camera, AR)
    * `:overlay` - can render above other content
    * `:clipping` - supports clipping masks
    * `:touch` - handles raw touch events
    * `:keyboard` - handles keyboard input
    * `:focus` - participates in focus navigation

  ## Example

      capability :gestures
      capability :accessibility
      capability :animation
  """
  defmacro capability(capability) do
    quote do
      Dala.Plugin.ComponentDSL.add_capability(
        __MODULE__,
        unquote(capability)
      )
    end
  end

  # Internal storage for component being built
  @doc false
  def add_prop(module, name, type, opts) do
    key = {:__dala_component__, module}

    component =
      case Process.get(key) do
        nil ->
          # If not in process dictionary, try to get from module attribute
          # This allows the function to work during macro expansion
          case Module.get_attribute(module, :__dala_component) do
            nil -> raise "Component not initialized. Call component/2 first."
            comp -> comp
          end

        comp ->
          comp
      end

    new_component = Component.add_prop(component, name, type, opts)

    # Store back
    case Process.get(key) do
      nil -> Module.put_attribute(module, :__dala_component, new_component)
      _ -> Process.put(key, new_component)
    end

    new_component
  end

  @doc false
  def add_event(module, name, opts) do
    key = {:__dala_component__, module}

    component =
      case Process.get(key) do
        nil ->
          case Module.get_attribute(module, :__dala_component) do
            nil -> raise "Component not initialized. Call component/2 first."
            comp -> comp
          end

        comp ->
          comp
      end

    new_component = Component.add_event(component, name, opts)

    case Process.get(key) do
      nil -> Module.put_attribute(module, :__dala_component, new_component)
      _ -> Process.put(key, new_component)
    end

    new_component
  end

  @doc false
  def add_native(module, platform, class_name) do
    key = {:__dala_component__, module}

    component =
      case Process.get(key) do
        nil ->
          case Module.get_attribute(module, :__dala_component) do
            nil -> raise "Component not initialized. Call component/2 first."
            comp -> comp
          end

        comp ->
          comp
      end

    new_component = Component.add_native(component, platform, class_name)

    case Process.get(key) do
      nil -> Module.put_attribute(module, :__dala_component, new_component)
      _ -> Process.put(key, new_component)
    end

    new_component
  end

  @doc false
  def add_capability(module, capability) do
    key = {:__dala_component__, module}

    component =
      case Process.get(key) do
        nil ->
          case Module.get_attribute(module, :__dala_component) do
            nil -> raise "Component not initialized. Call component/2 first."
            comp -> comp
          end

        comp ->
          comp
      end

    new_component = Component.add_capability(component, capability)

    case Process.get(key) do
      nil -> Module.put_attribute(module, :__dala_component, new_component)
      _ -> Process.put(key, new_component)
    end

    new_component
  end

  @doc false
  def get_component(module) do
    case Process.get({:__dala_component__, module}) do
      nil ->
        case Module.get_attribute(module, :__dala_component) do
          nil -> raise "Component not initialized. Call component/2 first."
          comp -> comp
        end

      comp ->
        comp
    end
  end

  @doc false
  def put_component(module, component) do
    key = {:__dala_component__, module}
    Process.put(key, component)
    Module.put_attribute(module, :__dala_component, component)
    component
  end
end
