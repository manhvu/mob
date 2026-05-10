defmodule Dala.Plugin do
  @moduledoc """
  Behaviour and macros for self-describing component plugins.

  Plugins declare themselves declaratively, allowing Dala core to remain generic.
  Everything becomes a plugin: video, maps, charts, camera, ML views, custom renderers, AR, etc.

  ## Architecture

  Dala core knows almost nothing. Plugins self-describe through:

  - **Schema** - component metadata (props, events, capabilities)
  - **Protocol** - binary communication format (auto-generated)
  - **Native renderer** - platform-specific implementation (iOS/Android)

  This is the same pattern used by:
  - React Native Fabric
  - Flutter Engine
  - SwiftUI internals
  - Jetpack Compose runtime
  - VSCode extension host
  - Browser DOM

  ## Example (top-level DSL)

      defmodule MyApp.VideoPlugin do
        use Dala.Plugin

        component "video" do
          prop "source", :string
          prop "autoplay", :bool
          prop "controls", :bool
          prop "volume", :f32

          event "progress"
          event "ended"
          event "ready"

          native "ios", "DalaVideoView"
          native "android", "com.dala.video.VideoView"

          capability :gestures
          capability :accessibility
          capability :animation
        end
      end

  ## Example (plugin do block)

      defmodule MyApp.VideoPlugin do
        use Dala.Plugin

        plugin do
          plugin_description "Video playback plugin"

          component "video", MyApp.VideoComponent
          plugin_event "video_zoom", MyApp.Video.Events.Zoom

          plugin_native :ios, MyApp.Video.IOS
          plugin_native :android, MyApp.Video.Android

          plugin_permission :camera
          plugin_dependency {:maps, "~> 1.0"}
          plugin_platform :ios
          plugin_platform :android
        end
      end

  ## Behaviour

  Modules using `Dala.Plugin` must implement (or get defaults for) these callbacks:

  - `init(opts)` → `{:ok, state}` | `{:error, reason}` — resource allocation (required)
  - `components()` → `[Component.t()]` — declare components (required)
  - `capabilities()` → `[atom()]` — what this plugin provides (required)
  - `permissions()` → `[atom()]` — declare required permissions (optional, default `[]`)
  - `native_modules(platform)` → `[module()]` — platform-specific native modules (optional, default `[]`)
  - `dependencies()` → `[{atom(), String.t()}]` — dependency ordering (optional, default `[]`)
  - `validate_config(config)` → `:ok` | `{:error, reason}` — compile-time hooks (optional, default `:ok`)
  - `handle_event(event, payload, state)` → `{:ok, state}` | `{:error, reason}` — runtime hooks (optional, default `{:ok, state}`)
  - `cleanup(state)` → `:ok` — resource deallocation / hot reload (optional, default `:ok`)

  ## Versioning

  Plugins MUST declare versions for compatibility:

      schema_version "1.0.0"
      protocol_version 3
      native_api_version "2.0.0"

  This prevents ecosystem fragmentation.

  ## Host/Runtime Separation

  Plugins should NEVER directly access:

  - BEAM internals
  - Scheduler state
  - Raw protocol sockets

  Instead:

      Plugin
         ↓
      Host API
         ↓
      Dala Runtime

  Exactly like browser extensions.

  ## Generic Node Model

  Everything becomes a generic node:

      %Dala.Node{
        type: "video",
        props: %{source: "...", autoplay: true},
        children: []
      }

  Dala core NEVER special-cases video, maps, or charts.
  The same generic lifecycle applies to all plugins:

  - create/2
  - update/2
  - layout/2
  - event/3
  - dispose/1

  Optional capabilities:
  - animate/2
  - focus/2
  - accessibility/2
  - snapshot/1
  - texture/1
  - gesture/2

  ## Universal Command Stream

  Dala core emits only generic operations:

  - CREATE_NODE
  - UPDATE_PROP
  - REMOVE_NODE
  - EMIT_EVENT
  - RUN_ANIMATION

  Plugins interpret semantics. Core stays tiny.
  """

  @type plugin_name :: atom()
  @type component_name :: String.t()
  @type prop_name :: String.t()
  @type prop_type ::
          :string | :bool | :integer | :float | :f32 | :f64 | :color | :binary | :list | :map
  @type event_name :: String.t()
  @type capability ::
          :gestures
          | :accessibility
          | :animation
          | :textures
          | :overlay
          | :clipping
          | :touch
          | :keyboard
          | :focus
  @type platform :: :ios | :android | :web
  @type status :: :registered | :initialized | :active | :error | :unloaded

  defstruct [
    :name,
    :description,
    :schema_version,
    :plugin_version,
    :protocol_version,
    :native_api_version,
    components: %{},
    permissions: [],
    dependencies: [],
    platforms: [],
    capabilities: [],
    events: %{},
    dala_requires: nil,
    state: nil,
    status: :registered,
    native_modules: %{},
    metadata: %{}
  ]

  # ── Behaviour ──────────────────────────────────────────────────────────────

  @doc """
  Initializes the plugin. Allocates resources, starts processes, etc.
  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Returns the list of component schemas this plugin provides.
  """
  @callback components() :: [Dala.Plugin.Component.t()]

  @doc """
  Returns the list of capabilities this plugin provides.
  """
  @callback capabilities() :: [atom()]

  @doc """
  Returns the list of permissions this plugin requires.
  """
  @callback permissions() :: [atom()]

  @doc """
  Returns platform-specific native modules for the given platform.
  """
  @callback native_modules(platform :: platform()) :: [module()]

  @doc """
  Returns dependency specifications: `{plugin_name, version_requirement}`.
  """
  @callback dependencies() :: [{atom(), String.t()}]

  @doc """
  Validates plugin configuration at compile-time.
  """
  @callback validate_config(config :: map()) :: :ok | {:error, reason :: term()}

  @doc """
  Handles runtime events sent to the plugin.
  """
  @callback handle_event(event :: atom(), payload :: map(), state :: term()) ::
              {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Cleans up resources before hot reload or unload.
  """
  @callback cleanup(state :: term()) :: :ok

  # ── use macro ──────────────────────────────────────────────────────────────

  @doc """
  Defines a new plugin module.

  ## Options

    * `:schema_version` - Plugin schema version (default: "1.0.0")
    * `:protocol_version` - Binary protocol version (default: 3)
    * `:native_api_version` - Native API version (default: "2.0.0")
    * `:platforms` - List of supported platforms (e.g. [:ios, :android])
    * `:capabilities` - List of plugin-level capabilities
    * `:dala_requires` - Dala version requirement string
    * `:metadata` - Arbitrary metadata map
  """
  defmacro __using__(opts \\ []) do
    plugin_name = opts[:name]
    plugin_version = opts[:version]
    plugin_platforms = opts[:platforms] || []
    plugin_dala_requires = opts[:dala_requires]
    plugin_capabilities = opts[:capabilities] || []
    plugin_metadata = opts[:metadata] || %{}

    quote bind_quoted: [
            plugin_name: plugin_name,
            plugin_version: plugin_version,
            plugin_platforms: plugin_platforms,
            plugin_dala_requires: plugin_dala_requires,
            plugin_capabilities: plugin_capabilities,
            plugin_metadata: plugin_metadata
          ] do
      @behaviour Dala.Plugin

      import Dala.Plugin
      import Dala.Plugin.ComponentDSL

      @before_compile Dala.Plugin

      @plugin_opts []
      Module.register_attribute(__MODULE__, :plugin_components, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_schema_version, accumulate: false)
      Module.register_attribute(__MODULE__, :plugin_protocol_version, accumulate: false)
      Module.register_attribute(__MODULE__, :plugin_native_api_version, accumulate: false)
      Module.register_attribute(__MODULE__, :plugin_description, accumulate: false)
      Module.register_attribute(__MODULE__, :plugin_permissions, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_dependencies, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_platforms, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_native_module_decls, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_block_used, accumulate: false)
      Module.register_attribute(__MODULE__, :plugin_events, accumulate: true)

      # Plugin block declarations (from `plugin do ... end`)
      Module.register_attribute(__MODULE__, :plugin_block_components, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_block_events, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_block_natives, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_block_permissions, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_block_dependencies, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_block_platforms, accumulate: true)
      Module.register_attribute(__MODULE__, :plugin_block_description, accumulate: false)
      Module.register_attribute(__MODULE__, :plugin_inline_events, accumulate: true)

      # Metadata from use options (always set with defaults)
      @plugin_name plugin_name
      @plugin_version plugin_version
      @plugin_platforms_from_opts plugin_platforms
      @plugin_dala_requires plugin_dala_requires
      @plugin_capabilities_from_opts plugin_capabilities
      @plugin_metadata plugin_metadata

      schema_version("1.0.0")
      protocol_version(3)
      native_api_version("2.0.0")
    end
  end

  # ── Top-level DSL macros ───────────────────────────────────────────────────

  @doc """
  Defines a new component within the plugin.

  ## Example

      component "video" do
        prop "source", :string
        prop "autoplay", :bool
        prop "volume", :f32

        event "progress"
        event "ended"

        native "ios", "DalaVideoView"
        native "android", "com.dala.video.VideoView"

        capability :gestures
        capability :accessibility
      end
  """
  defmacro component(name, do: block) when is_binary(name) do
    quote do
      component_schema = %Dala.Plugin.Component{
        name: unquote(name),
        plugin: __MODULE__
      }

      Module.register_attribute(__MODULE__, :__dala_component, [])
      Module.put_attribute(__MODULE__, :__dala_component, component_schema)

      unquote(block)

      component_schema = Module.get_attribute(__MODULE__, :__dala_component)
      Module.delete_attribute(__MODULE__, :__dala_component)

      @plugin_components component_schema
    end
  end

  defmacro component(name, module) when is_atom(name) do
    quote do
      Dala.Plugin.plugin_component(unquote(name), unquote(module))
    end
  end

  defmacro component(name, module) when is_binary(name) do
    quote do
      Dala.Plugin.plugin_component(unquote(name), unquote(module))
    end
  end

  @doc """
  Sets the plugin schema version.
  """
  defmacro schema_version(version) when is_binary(version) do
    quote do
      @plugin_schema_version unquote(version)
    end
  end

  @doc """
  Sets the binary protocol version.
  """
  defmacro protocol_version(version) when is_integer(version) do
    quote do
      @plugin_protocol_version unquote(version)
    end
  end

  @doc """
  Sets the native API version.
  """
  defmacro native_api_version(version) when is_binary(version) do
    quote do
      @plugin_native_api_version unquote(version)
    end
  end

  @doc """
  Sets the plugin description.
  """
  defmacro description(text) when is_binary(text) do
    quote do
      @plugin_description unquote(text)
    end
  end

  @doc """
  Declares a permission the plugin requires.
  """
  defmacro permission(name) when is_atom(name) do
    quote do
      @plugin_permissions unquote(name)
    end
  end

  @doc """
  Declares a dependency on another plugin with a version requirement.
  """
  defmacro dependency({name, version_req}) do
    quote do
      @plugin_dependencies {unquote(name), unquote(version_req)}
    end
  end

  @doc """
  Declares platform support.
  """
  defmacro platform(name) when name in [:ios, :android, :web] do
    quote do
      @plugin_platforms unquote(name)
    end
  end

  @doc """
  Declares a native module for a specific platform.
  """
  defmacro native_module(platform, module) when platform in [:ios, :android, :web] do
    quote do
      @plugin_native_module_decls {unquote(platform), unquote(module)}
    end
  end

  # ── plugin do block DSL ────────────────────────────────────────────────────

  @doc """
  Main entry point for the plugin DSL block.

  Inside a `plugin do` block, you can declare:

  - `component :chart, MyPlugin.ChartComponent`
  - `plugin_event :chart_zoom, MyPlugin.Events.Zoom`
  - `plugin_native :ios, MyPlugin.IOS`
  - `plugin_native :android, MyPlugin.Android`
  - `plugin_permission :camera`
  - `plugin_dependency {:maps, "~> 1.0"}`
  - `plugin_platform :ios`
  - `plugin_platform :android`
  - `plugin_description "My chart plugin"`

  If `plugin do` is used, it takes precedence for those declarations.
  """
  defmacro plugin(do: block) do
    quote do
      @plugin_block_used true

      unquote(block)
    end
  end

  @doc false
  defmacro plugin_component(name, module) when is_binary(name) do
    quote do
      component_schema = %Dala.Plugin.Component{
        name: unquote(name),
        plugin: __MODULE__
      }

      @plugin_block_components {unquote(name), unquote(module), component_schema}
      @plugin_components component_schema
    end
  end

  @doc false
  defmacro plugin_component(name, module) when is_atom(name) do
    quote do
      component_name = Atom.to_string(unquote(name))

      component_schema = %Dala.Plugin.Component{
        name: component_name,
        plugin: __MODULE__
      }

      @plugin_block_components {component_name, unquote(module), component_schema}
      @plugin_components component_schema
    end
  end

  @doc false
  defmacro plugin_event(name, module) when is_atom(name) and is_atom(module) do
    quote do
      @plugin_block_events {unquote(name), unquote(module)}
    end
  end

  @doc false
  defmacro plugin_event(name, payload) when is_atom(name) and is_map(payload) do
    event_mod = Dala.Plugin.Event.event_module_name(name, __MODULE__)

    quote do
      @plugin_block_events {unquote(name), unquote(event_mod)}
      @plugin_inline_events {unquote(name), unquote(Macro.escape(payload))}
    end
  end

  @doc false
  defmacro plugin_native(platform, module) when platform in [:ios, :android, :web] do
    quote do
      @plugin_block_natives {unquote(platform), unquote(module)}
      @plugin_native_module_decls {unquote(platform), unquote(module)}
    end
  end

  @doc false
  defmacro plugin_permission(name) when is_atom(name) do
    quote do
      @plugin_block_permissions unquote(name)
      @plugin_permissions unquote(name)
    end
  end

  @doc false
  defmacro plugin_dependency({name, version_req}) when is_atom(name) and is_binary(version_req) do
    quote do
      @plugin_block_dependencies {unquote(name), unquote(version_req)}
      @plugin_dependencies {unquote(name), unquote(version_req)}
    end
  end

  @doc false
  defmacro plugin_platform(name) when name in [:ios, :android, :web] do
    quote do
      @plugin_block_platforms unquote(name)
      @plugin_platforms unquote(name)
    end
  end

  @doc false
  defmacro plugin_description(text) when is_binary(text) do
    quote do
      @plugin_block_description unquote(text)
      @plugin_description unquote(text)
    end
  end

  # ── __before_compile__ ─────────────────────────────────────────────────────

  @doc """
  Macro callback - builds the full plugin struct and generates default
  behaviour implementations.
  """
  defmacro __before_compile__(_env) do
    quote do
      # ── Compute and store all derived values as module attributes ────────

      _plugin_name =
        if Module.get_attribute(__MODULE__, :plugin_name) do
          Module.get_attribute(__MODULE__, :plugin_name)
        else
          __MODULE__
        end

      Module.register_attribute(__MODULE__, :__dala_plugin_name, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_plugin_name, _plugin_name)

      _plugin_version =
        if Module.get_attribute(__MODULE__, :plugin_version) do
          Module.get_attribute(__MODULE__, :plugin_version)
        else
          nil
        end

      Module.register_attribute(__MODULE__, :__dala_plugin_version, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_plugin_version, _plugin_version)

      _dala_requires =
        if Module.get_attribute(__MODULE__, :plugin_dala_requires) do
          Module.get_attribute(__MODULE__, :plugin_dala_requires)
        else
          nil
        end

      Module.register_attribute(__MODULE__, :__dala_requires, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_dala_requires, _dala_requires)

      _native_modules_map =
        case Module.get_attribute(__MODULE__, :plugin_block_used) do
          true ->
            block_natives = Module.get_attribute(__MODULE__, :plugin_block_natives) || []

            Enum.reduce(block_natives, %{}, fn {platform, module}, acc ->
              Map.update(acc, platform, [module], fn existing -> existing ++ [module] end)
            end)

          _ ->
            decls = Module.get_attribute(__MODULE__, :plugin_native_module_decls) || []

            Enum.reduce(decls, %{}, fn {platform, module}, acc ->
              Map.update(acc, platform, [module], fn existing -> existing ++ [module] end)
            end)
        end

      Module.register_attribute(__MODULE__, :__dala_native_modules_map, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_native_modules_map, _native_modules_map)

      _permissions_list =
        case Module.get_attribute(__MODULE__, :plugin_block_used) do
          true ->
            block_perms = Module.get_attribute(__MODULE__, :plugin_block_permissions) || []
            Enum.reverse(block_perms)

          _ ->
            top_perms = Module.get_attribute(__MODULE__, :plugin_permissions) || []
            Enum.reverse(top_perms)
        end

      Module.register_attribute(__MODULE__, :__dala_permissions_list, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_permissions_list, _permissions_list)

      _dependencies_list =
        case Module.get_attribute(__MODULE__, :plugin_block_used) do
          true ->
            block_deps = Module.get_attribute(__MODULE__, :plugin_block_dependencies) || []
            Enum.reverse(block_deps)

          _ ->
            top_deps = Module.get_attribute(__MODULE__, :plugin_dependencies) || []
            Enum.reverse(top_deps)
        end

      Module.register_attribute(__MODULE__, :__dala_dependencies_list, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_dependencies_list, _dependencies_list)

      _platforms_list =
        case Module.get_attribute(__MODULE__, :plugin_block_used) do
          true ->
            block_platforms = Module.get_attribute(__MODULE__, :plugin_block_platforms) || []
            Enum.reverse(block_platforms)

          _ ->
            raw = Module.get_attribute(__MODULE__, :plugin_platforms) || []
            opts_platforms = Module.get_attribute(__MODULE__, :plugin_platforms_from_opts) || []
            Enum.uniq(raw ++ opts_platforms)
        end

      Module.register_attribute(__MODULE__, :__dala_platforms_list, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_platforms_list, _platforms_list)

      _description_val =
        case Module.get_attribute(__MODULE__, :plugin_block_used) do
          true -> Module.get_attribute(__MODULE__, :plugin_block_description)
          _ -> Module.get_attribute(__MODULE__, :plugin_description)
        end

      Module.register_attribute(__MODULE__, :__dala_description_val, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_description_val, _description_val)

      _capabilities_from_opts =
        Module.get_attribute(__MODULE__, :plugin_capabilities_from_opts) || []

      _components_map =
        case Module.get_attribute(__MODULE__, :plugin_components) do
          nil -> %{}
          comps -> Enum.into(Enum.reverse(comps), %{}, &{&1.name, &1})
        end

      Module.register_attribute(__MODULE__, :__dala_components_map, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_components_map, _components_map)

      _all_capabilities =
        _components_map
        |> Enum.flat_map(fn {_name, comp} -> comp.capabilities end)
        |> Enum.concat(_capabilities_from_opts)
        |> Enum.uniq()

      Module.register_attribute(__MODULE__, :__dala_all_capabilities, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_all_capabilities, _all_capabilities)

      _metadata = Module.get_attribute(__MODULE__, :plugin_metadata) || %{}

      Module.register_attribute(__MODULE__, :__dala_metadata, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_metadata, _metadata)

      # ── Generate event struct modules ─────────────────────────────────────
      _events_map =
        case Module.get_attribute(__MODULE__, :plugin_components) do
          nil ->
            %{}

          comps ->
            Enum.reduce(comps, %{}, fn comp, acc ->
              Enum.reduce(comp.events, acc, fn evt, inner_acc ->
                if evt.payload != %{} do
                  event_atom = String.to_atom(evt.name)
                  mod = Dala.Plugin.Event.event_module_name(event_atom, __MODULE__)

                  quote do
                    Dala.Plugin.Event.expand(
                      unquote(event_atom),
                      unquote(Macro.escape(evt.payload)),
                      __MODULE__
                    )
                  end
                  |> Code.eval_quoted([], __ENV__)

                  Map.put(inner_acc, event_atom, mod)
                else
                  inner_acc
                end
              end)
            end)
        end

      # Generate event struct modules for inline events from plugin do block
      _inline_events_map =
        case Module.get_attribute(__MODULE__, :plugin_inline_events) do
          nil ->
            %{}

          inline_events ->
            Enum.reduce(inline_events, %{}, fn {evt_name, payload}, acc ->
              event_atom = evt_name
              mod = Dala.Plugin.Event.event_module_name(event_atom, __MODULE__)

              quote do
                Dala.Plugin.Event.expand(
                  unquote(event_atom),
                  unquote(Macro.escape(payload)),
                  __MODULE__
                )
              end
              |> Code.eval_quoted([], __ENV__)

              Map.put(acc, event_atom, mod)
            end)
        end

      # Merge component events and inline events
      _merged_events_map = Map.merge(_events_map, _inline_events_map)

      Module.register_attribute(__MODULE__, :__dala_events_map, accumulate: false)
      Module.put_attribute(__MODULE__, :__dala_events_map, _merged_events_map)

      # ── Plugin info struct ────────────────────────────────────────────────
      @doc false
      def __plugin_info__ do
        %Dala.Plugin{
          name: @__dala_plugin_name,
          description: @__dala_description_val,
          schema_version: @plugin_schema_version,
          plugin_version: @__dala_plugin_version,
          protocol_version: @plugin_protocol_version,
          native_api_version: @plugin_native_api_version,
          components: @__dala_components_map,
          permissions: @__dala_permissions_list,
          dependencies: @__dala_dependencies_list,
          platforms: @__dala_platforms_list,
          capabilities: @__dala_all_capabilities,
          events: @__dala_events_map,
          dala_requires: @__dala_dala_requires,
          state: nil,
          status: :registered,
          native_modules: @__dala_native_modules_map,
          metadata: @__dala_metadata
        }
      end

      # ── Behaviour implementations ─────────────────────────────────────────

      @doc """
      Registers this plugin with the Dala runtime.
      """
      def register do
        Dala.Plugin.Registry.register(__plugin_info__())
      end

      @doc """
      Returns the component schema by name.
      """
      def component(name) when is_binary(name) do
        Map.get(__plugin_info__().components, name)
      end

      @doc """
      Returns all component schemas as a map.
      """
      def components do
        __plugin_info__().components
      end

      @doc """
      Returns all component schemas as a list (behaviour callback).
      """
      def components_list do
        __plugin_info__().components |> Map.values()
      end

      @doc """
      Returns the list of capabilities this plugin provides (behaviour callback).
      """
      def capabilities do
        __plugin_info__().capabilities
      end

      @doc """
      Returns the list of permissions this plugin requires (behaviour callback).
      """
      def permissions do
        __plugin_info__().permissions
      end

      @doc """
      Returns platform-specific native modules (behaviour callback).
      """
      def native_modules(platform) when platform in [:ios, :android, :web] do
        Map.get(__plugin_info__().native_modules, platform, [])
      end

      @doc """
      Returns dependency specifications (behaviour callback).
      """
      def dependencies do
        __plugin_info__().dependencies
      end

      @doc """
      Validates plugin configuration (behaviour callback, default: :ok).
      """
      def validate_config(_config), do: :ok

      @doc """
      Handles runtime events (behaviour callback, default: {:ok, state}).
      """
      def handle_event(_event, _payload, state), do: {:ok, state}

      @doc """
      Initializes the plugin (behaviour callback, default: {:ok, nil}).
      """
      def init(_opts), do: {:ok, nil}

      @doc """
      Cleans up resources (behaviour callback, default: :ok).
      """
      def cleanup(_state), do: :ok

      @doc """
      Generates the binary protocol specification for this plugin.
      """
      def generate_protocol do
        Dala.Plugin.Protocol.generate(__plugin_info__())
      end

      @doc """
      Generates the plugin manifest for native platforms.
      """
      def generate_manifest do
        Dala.Plugin.Manifest.generate(__plugin_info__())
      end

      @doc """
      Auto-registers the plugin if configured.
      """
      def __auto_register__ do
        if Application.get_env(:dala, :auto_register_plugins, true) do
          register()
        end
      end

      # Allow user overrides of optional callbacks
      defoverridable init: 1,
                     components: 0,
                     capabilities: 0,
                     permissions: 0,
                     native_modules: 1,
                     dependencies: 0,
                     validate_config: 1,
                     handle_event: 3,
                     cleanup: 1
    end
  end

  # ── Utility ────────────────────────────────────────────────────────────────

  @doc """
  Auto-registers all plugins found in loaded applications.
  """
  def auto_register do
    apps = Application.loaded_applications() |> Enum.map(fn {app, _, _} -> app end)

    for app <- apps do
      try do
        app_modules = Application.spec(app, :modules) || []

        for module <- app_modules do
          try do
            behaviours =
              module.module_info(:attributes)
              |> Enum.find_value([], fn
                {:__behaviour__, [Dala.Plugin]} -> true
                _ -> false
              end)

            if behaviours do
              module.__auto_register__()
            end
          rescue
            _ -> :ok
          end
        end
      rescue
        _ -> :ok
      end
    end

    :ok
  end
end
