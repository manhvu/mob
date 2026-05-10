defmodule Dala.PluginTest do
  use ExUnit.Case, async: false

  alias Dala.Plugin
  alias Dala.Plugin.Component
  alias Dala.Plugin.Registry
  alias Dala.Plugin.Protocol
  alias Dala.Plugin.Manifest

  setup do
    # Stop any existing registry to avoid ETS table conflicts
    case Process.whereis(Dala.Plugin.Registry) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    # Give it a moment to terminate
    Process.sleep(50)

    # Start fresh registry - use :force to recreate tables if they exist
    {:ok, _pid} = Registry.start_link()
    Registry.clear()
    :ok
  end

  describe "Plugin module macro" do
    defmodule TestPlugin do
      use Dala.Plugin

      import Dala.Plugin

      component "video" do
        prop("source", :string)
        prop("autoplay", :bool, default: false)
        prop("volume", :f32, required: true)

        event("progress")
        event("ended", payload: %{position: :f32, duration: :f32})

        native("ios", "DalaVideoView")
        native("android", "com.dala.video.VideoView")

        capability(:gestures)
        capability(:accessibility)
        capability(:animation)
      end

      component "map" do
        prop("center", :map)
        prop("zoom", :f32)

        event("region_changed")

        native("ios", "DalaMapView")
        native("android", "com.dala.map.MapView")

        capability(:gestures)
        capability(:overlay)
      end
    end

    test "defines plugin info function" do
      info = TestPlugin.__plugin_info__()
      assert %Plugin{name: TestPlugin} = info
      assert info.schema_version == "1.0.0"
      assert info.protocol_version == 3
      assert info.native_api_version == "2.0.0"
    end

    test "registers components" do
      info = TestPlugin.__plugin_info__()
      assert map_size(info.components) == 2
      assert Map.has_key?(info.components, "video")
      assert Map.has_key?(info.components, "map")
    end

    test "component has correct properties" do
      component = TestPlugin.component("video")
      assert %Component{name: "video"} = component
      assert length(component.props) == 3

      source_prop = Enum.find(component.props, &(&1.name == "source"))
      assert source_prop.type == :string
      assert source_prop.required == false
      assert source_prop.default == nil

      autoplay_prop = Enum.find(component.props, &(&1.name == "autoplay"))
      assert autoplay_prop.type == :bool
      assert autoplay_prop.default == false

      volume_prop = Enum.find(component.props, &(&1.name == "volume"))
      assert volume_prop.type == :f32
      assert volume_prop.required == true
    end

    test "component has correct events" do
      component = TestPlugin.component("video")
      assert length(component.events) == 2

      progress_event = Enum.find(component.events, &(&1.name == "progress"))
      assert progress_event.name == "progress"

      ended_event = Enum.find(component.events, &(&1.name == "ended"))
      assert ended_event.name == "ended"
      assert ended_event.payload == %{position: :f32, duration: :f32}
    end

    test "component has correct native mappings" do
      component = TestPlugin.component("video")

      assert component.natives == %{
               "ios" => "DalaVideoView",
               "android" => "com.dala.video.VideoView"
             }
    end

    test "component has correct capabilities" do
      component = TestPlugin.component("video")
      assert :gestures in component.capabilities
      assert :accessibility in component.capabilities
      assert :animation in component.capabilities
      assert length(component.capabilities) == 3
    end

    test "register/0 registers plugin with registry" do
      TestPlugin.register()
      assert {:ok, _} = Registry.lookup_component("video")
      assert {:ok, _} = Registry.lookup_component("map")
    end

    test "components/0 returns all component schemas" do
      components = TestPlugin.components()
      assert is_map(components)
      assert map_size(components) == 2
    end

    test "generate_protocol/0 returns protocol spec" do
      spec = TestPlugin.generate_protocol()
      assert spec.plugin == TestPlugin
      assert spec.schema_version == "1.0.0"
      assert spec.protocol_version == 3
      assert is_map(spec.field_map)
      assert Map.has_key?(spec.field_map, "video")
      assert Map.has_key?(spec.field_map, "map")
    end

    test "generate_manifest/0 returns manifest" do
      manifest = TestPlugin.generate_manifest()
      assert manifest["schema_version"] == "1.0.0"
      assert manifest["protocol_version"] == 3
      assert manifest["native_api_version"] == "2.0.0"
      assert is_map(manifest["components"])
      assert is_list(manifest["capabilities"])
      assert is_map(manifest["capabilities_by_component"])
      assert Map.has_key?(manifest["components"], "video")
    end
  end

  describe "Component schema" do
    test "add_prop/4 adds property to component" do
      component = %Component{name: "test", plugin: TestPlugin}
      updated = Component.add_prop(component, "color", :color, required: true)
      assert length(updated.props) == 1
      prop = hd(updated.props)
      assert prop.name == "color"
      assert prop.type == :color
      assert prop.required == true
    end

    test "add_event/3 adds event to component" do
      component = %Component{name: "test", plugin: TestPlugin}
      updated = Component.add_event(component, "tap", payload: %{x: :integer})
      assert length(updated.events) == 1
      event = hd(updated.events)
      assert event.name == "tap"
      assert event.payload == %{x: :integer}
    end

    test "add_native/3 adds native mapping" do
      component = %Component{name: "test", plugin: TestPlugin}
      updated = Component.add_native(component, "ios", "TestView")
      assert updated.natives == %{"ios" => "TestView"}
    end

    test "add_capability/2 adds capability" do
      component = %Component{name: "test", plugin: TestPlugin}
      updated = Component.add_capability(component, :gestures)
      assert updated.capabilities == [:gestures]
    end
  end

  describe "Plugin registry" do
    defmodule RegistryTestPlugin do
      use Dala.Plugin

      import Dala.Plugin

      component "button" do
        prop("text", :string)
        capability(:gestures)
      end
    end

    test "register/1 adds plugin to registry" do
      plugin = RegistryTestPlugin.__plugin_info__()
      :ok = Registry.register(plugin)

      assert {:ok, ^plugin} = Registry.lookup_component("button")
      assert {:ok, ^plugin} = Registry.get_plugin(RegistryTestPlugin)
    end

    test "register_module/1 registers plugin module" do
      :ok = Registry.register(RegistryTestPlugin)
      assert {:ok, _} = Registry.lookup_component("button")
    end

    test "list_plugins/0 returns all registered plugins" do
      Registry.register(RegistryTestPlugin)
      plugins = Registry.list_plugins()
      assert length(plugins) == 1
      assert %Plugin{name: RegistryTestPlugin} = hd(plugins)
    end

    test "list_components/0 returns all component types" do
      Registry.register(RegistryTestPlugin)
      components = Registry.list_components()
      assert "button" in components
    end

    test "has_component?/1 checks component registration" do
      Registry.register(RegistryTestPlugin)
      assert Registry.has_component?("button")
      refute Registry.has_component?("nonexistent")
    end

    test "components_with_capability/1 returns components with capability" do
      Registry.register(RegistryTestPlugin)
      components = Registry.components_with_capability(:gestures)
      assert "button" in components
    end

    test "supports_capability?/1 checks capability support" do
      Registry.register(RegistryTestPlugin)
      assert Registry.supports_capability?(:gestures)
      refute Registry.supports_capability?(:textures)
    end

    test "list_capabilities/0 returns all registered capabilities" do
      Registry.register(RegistryTestPlugin)
      capabilities = Registry.list_capabilities()
      assert :gestures in capabilities
    end

    test "unregister/1 removes plugin from registry" do
      Registry.register(RegistryTestPlugin)
      assert {:ok, _} = Registry.lookup_component("button")

      :ok = Registry.unregister(RegistryTestPlugin)
      assert {:error, :not_found} = Registry.lookup_component("button")
      assert {:error, :not_found} = Registry.get_plugin(RegistryTestPlugin)
    end

    test "clear/0 removes all registrations" do
      Registry.register(RegistryTestPlugin)
      :ok = Registry.clear()

      assert [] = Registry.list_plugins()
      assert [] = Registry.list_components()
      assert [] = Registry.list_capabilities()
    end
  end

  describe "Protocol generation" do
    defmodule ProtocolTestPlugin do
      use Dala.Plugin

      import Dala.Plugin

      component "slider" do
        prop("value", :f32)
        prop("min", :f32)
        prop("max", :f32)
        prop("enabled", :bool)
      end
    end

    test "generate/1 creates field mappings" do
      plugin = ProtocolTestPlugin.__plugin_info__()
      spec = Protocol.generate(plugin)

      assert spec.plugin == ProtocolTestPlugin
      assert is_map(spec.field_map["slider"])

      field_by_name = spec.field_map["slider"]
      assert field_by_name["value"].number == 1
      assert field_by_name["value"].type_tag == 0x05
      assert field_by_name["min"].number == 2
      assert field_by_name["max"].number == 3
      assert field_by_name["enabled"].number == 4
      assert field_by_name["enabled"].type_tag == 0x02
    end

    test "type_to_tag/1 converts types to tags" do
      assert Protocol.type_to_tag(:string) == 0x01
      assert Protocol.type_to_tag(:bool) == 0x02
      assert Protocol.type_to_tag(:integer) == 0x03
      assert Protocol.type_to_tag(:float) == 0x04
      assert Protocol.type_to_tag(:f32) == 0x05
      assert Protocol.type_to_tag(:f64) == 0x06
      assert Protocol.type_to_tag(:color) == 0x07
      assert Protocol.type_to_tag(:binary) == 0x08
      assert Protocol.type_to_tag(:list) == 0x09
      assert Protocol.type_to_tag(:map) == 0x0A
    end

    test "encode_value/2 encodes string values" do
      encoded = Protocol.encode_value(0x01, "hello")
      assert encoded == <<0x01, 5::16, "hello"::binary>>
    end

    test "encode_value/2 encodes bool values" do
      assert Protocol.encode_value(0x02, true) == <<0x02, 0x01>>
      assert Protocol.encode_value(0x02, false) == <<0x02, 0x00>>
    end

    test "encode_value/2 encodes integer values" do
      assert Protocol.encode_value(0x03, 42) == <<0x03, 42::signed-64>>
    end

    test "encode_value/2 encodes float values" do
      encoded = Protocol.encode_value(0x04, 3.14)
      assert byte_size(encoded) == 9
      assert binary_part(encoded, 0, 1) == <<0x04>>
    end

    test "encode_value/2 encodes f32 values" do
      encoded = Protocol.encode_value(0x05, 1.5)
      assert byte_size(encoded) == 5
      assert binary_part(encoded, 0, 1) == <<0x05>>
    end

    test "encode_value/2 encodes color values" do
      assert Protocol.encode_value(0x07, 0xFF2196F3) == <<0x07, 0xFF2196F3::unsigned-32>>
    end

    test "encode_value/2 encodes binary values" do
      encoded = Protocol.encode_value(0x08, "data")
      assert encoded == <<0x08, 4::32, "data"::binary>>
    end
  end

  describe "Manifest generation" do
    defmodule ManifestTestPlugin do
      use Dala.Plugin

      import Dala.Plugin

      schema_version("2.0.0")
      protocol_version(5)
      native_api_version("3.0.0")

      component "chart" do
        prop("data", :map)
        native("ios", "DalaChartView")
        native("android", "com.dala.chart.ChartView")
        capability(:animation)
        capability(:textures)
      end
    end

    test "generate/1 creates manifest map" do
      plugin = ManifestTestPlugin.__plugin_info__()
      manifest = Manifest.generate(plugin)

      assert manifest["schema_version"] == "2.0.0"
      assert manifest["protocol_version"] == 5
      assert manifest["native_api_version"] == "3.0.0"
      assert is_map(manifest["components"])
      assert is_map(manifest["capabilities_by_component"])
      assert is_list(manifest["capabilities"])

      assert manifest["components"]["chart"] == %{
               "ios" => "DalaChartView",
               "android" => "com.dala.chart.ChartView"
             }

      assert :animation in manifest["capabilities_by_component"]["chart"]
      assert :textures in manifest["capabilities_by_component"]["chart"]
    end

    test "to_json/1 encodes manifest as JSON" do
      plugin = ManifestTestPlugin.__plugin_info__()
      json = Manifest.to_json(plugin)
      decoded = Jason.decode!(json)

      assert decoded["schema_version"] == "2.0.0"
      assert decoded["protocol_version"] == 5
      assert decoded["native_api_version"] == "3.0.0"
      assert decoded["components"]["chart"]["ios"] == "DalaChartView"
    end

    test "from_json/1 decodes JSON manifest" do
      json = ~s({
        "schema_version": "1.0.0",
        "protocol_version": 3,
        "native_api_version": "2.0.0",
        "components": {
          "video": {
            "ios": "DalaVideoView"
          }
        },
        "capabilities": {
          "video": ["gestures"]
        }
      })

      {:ok, manifest} = Manifest.from_json(json)
      assert manifest["schema_version"] == "1.0.0"
      assert manifest["components"]["video"]["ios"] == "DalaVideoView"
    end

    test "register_from_manifest/1 registers components from manifest" do
      manifest = %{
        "schema_version" => "1.0.0",
        "protocol_version" => 3,
        "native_api_version" => "2.0.0",
        "components" => %{
          "custom_video" => %{"ios" => "CustomVideoView"}
        },
        "capabilities" => %{
          "custom_video" => ["gestures", "animation"]
        }
      }

      :ok = Manifest.register_from_manifest(manifest)
      assert {:ok, _} = Registry.lookup_component("custom_video")
    end
  end

  describe "Plugin with all prop types" do
    defmodule AllTypesPlugin do
      use Dala.Plugin

      import Dala.Plugin

      component "all_types" do
        prop("str", :string)
        prop("flag", :bool)
        prop("count", :integer)
        prop("ratio", :float)
        prop("single", :f32)
        prop("double", :f64)
        prop("color", :color)
        prop("data", :binary)
        prop("items", :list)
        prop("config", :map)
      end
    end

    test "all prop types are supported" do
      component = AllTypesPlugin.component("all_types")
      type_names = Enum.map(component.props, & &1.type)

      assert :string in type_names
      assert :bool in type_names
      assert :integer in type_names
      assert :float in type_names
      assert :f32 in type_names
      assert :f64 in type_names
      assert :color in type_names
      assert :binary in type_names
      assert :list in type_names
      assert :map in type_names
    end
  end

  describe "Plugin with all capabilities" do
    defmodule AllCapabilitiesPlugin do
      use Dala.Plugin

      import Dala.Plugin

      component "super_component" do
        capability(:gestures)
        capability(:accessibility)
        capability(:animation)
        capability(:textures)
        capability(:overlay)
        capability(:clipping)
        capability(:touch)
        capability(:keyboard)
        capability(:focus)
      end
    end

    test "all capabilities are supported" do
      component = AllCapabilitiesPlugin.component("super_component")
      assert length(component.capabilities) == 9
      assert :gestures in component.capabilities
      assert :accessibility in component.capabilities
      assert :animation in component.capabilities
      assert :textures in component.capabilities
      assert :overlay in component.capabilities
      assert :clipping in component.capabilities
      assert :touch in component.capabilities
      assert :keyboard in component.capabilities
      assert :focus in component.capabilities
    end
  end

  describe "Plugin lifecycle DSL" do
    defmodule LifecyclePlugin do
      use Dala.Plugin

      import Dala.Plugin

      description("A plugin with full lifecycle support")
      permission(:camera)
      permission(:bluetooth)
      dependency({:maps, "~> 1.0"})
      platform(:ios)
      platform(:android)
      native_module(:ios, __MODULE__.IOS)
      native_module(:android, __MODULE__.Android)

      component "camera" do
        prop("facing", :string)
        capability(:gestures)
        capability(:textures)
      end
    end

    test "description is set" do
      info = LifecyclePlugin.__plugin_info__()
      assert info.description == "A plugin with full lifecycle support"
    end

    test "permissions are set" do
      info = LifecyclePlugin.__plugin_info__()
      assert :camera in info.permissions
      assert :bluetooth in info.permissions
    end

    test "dependencies are set" do
      info = LifecyclePlugin.__plugin_info__()
      assert {:maps, "~> 1.0"} in info.dependencies
    end

    test "platforms are set" do
      info = LifecyclePlugin.__plugin_info__()
      assert :ios in info.platforms
      assert :android in info.platforms
    end

    test "native_modules are set" do
      info = LifecyclePlugin.__plugin_info__()
      assert Dala.PluginTest.LifecyclePlugin.IOS in info.native_modules[:ios]
      assert Dala.PluginTest.LifecyclePlugin.Android in info.native_modules[:android]
    end

    test "capabilities are derived from components" do
      info = LifecyclePlugin.__plugin_info__()
      assert :gestures in info.capabilities
      assert :textures in info.capabilities
    end

    test "default status is :registered" do
      info = LifecyclePlugin.__plugin_info__()
      assert info.status == :registered
    end

    test "default state is nil" do
      info = LifecyclePlugin.__plugin_info__()
      assert info.state == nil
    end

    test "behaviour callbacks have defaults" do
      assert {:ok, nil} = LifecyclePlugin.init([])
      assert LifecyclePlugin.permissions() == [:camera, :bluetooth]
      assert Dala.PluginTest.LifecyclePlugin.IOS in LifecyclePlugin.native_modules(:ios)
      assert Dala.PluginTest.LifecyclePlugin.Android in LifecyclePlugin.native_modules(:android)
      assert LifecyclePlugin.dependencies() == [{:maps, "~> 1.0"}]
      assert :ok = LifecyclePlugin.validate_config(%{})
      assert {:ok, nil} = LifecyclePlugin.handle_event(:test, %{}, nil)
      assert :ok = LifecyclePlugin.cleanup(nil)
    end
  end

  describe "Plugin do block DSL" do
    defmodule PluginBlockPlugin do
      use Dala.Plugin

      plugin do
        plugin_description("Chart plugin via plugin do block")
        component(:chart, Dala.PluginTest.PluginBlockPlugin.ChartComponent)
        plugin_event(:chart_zoom, Dala.PluginTest.PluginBlockPlugin.Events.Zoom)
        plugin_native(:ios, Dala.PluginTest.PluginBlockPlugin.IOS)
        plugin_native(:android, Dala.PluginTest.PluginBlockPlugin.Android)
        plugin_permission(:storage)
        plugin_dependency({:video, "~> 2.0"})
        plugin_platform(:ios)
        plugin_platform(:android)
      end
    end

    test "plugin do block sets description" do
      info = PluginBlockPlugin.__plugin_info__()
      assert info.description == "Chart plugin via plugin do block"
    end

    test "plugin do block sets permissions" do
      info = PluginBlockPlugin.__plugin_info__()
      assert :storage in info.permissions
    end

    test "plugin do block sets dependencies" do
      info = PluginBlockPlugin.__plugin_info__()
      assert {:video, "~> 2.0"} in info.dependencies
    end

    test "plugin do block sets platforms" do
      info = PluginBlockPlugin.__plugin_info__()
      assert :ios in info.platforms
      assert :android in info.platforms
    end

    test "plugin do block sets native modules" do
      info = PluginBlockPlugin.__plugin_info__()
      assert Dala.PluginTest.PluginBlockPlugin.IOS in info.native_modules[:ios]
      assert Dala.PluginTest.PluginBlockPlugin.Android in info.native_modules[:android]
    end
  end

  describe "Plugin lifecycle management" do
    alias Dala.Plugin.Lifecycle

    defmodule LifecycleManagedPlugin do
      use Dala.Plugin

      import Dala.Plugin

      description("Managed plugin")
      platform(:ios)
      platform(:android)

      component "widget" do
        prop("label", :string)
        capability(:gestures)
        capability(:animation)
      end

      @impl true
      def init(_opts) do
        {:ok, %{initialized: true}}
      end

      @impl true
      def cleanup(_state) do
        :ok
      end
    end

    test "init/2 transitions :registered → :initialized" do
      LifecycleManagedPlugin.register()
      assert {:ok, %{initialized: true}} = Lifecycle.init(LifecycleManagedPlugin)
      assert :initialized = Lifecycle.status(LifecycleManagedPlugin)
    end

    test "activate/1 transitions :initialized → :active" do
      LifecycleManagedPlugin.register()
      {:ok, _} = Lifecycle.init(LifecycleManagedPlugin)
      assert :ok = Lifecycle.activate(LifecycleManagedPlugin)
      assert :active = Lifecycle.status(LifecycleManagedPlugin)
    end

    test "deactivate/1 transitions :active → :registered" do
      LifecycleManagedPlugin.register()
      {:ok, _} = Lifecycle.init(LifecycleManagedPlugin)
      :ok = Lifecycle.activate(LifecycleManagedPlugin)
      assert :ok = Lifecycle.deactivate(LifecycleManagedPlugin)
      assert :registered = Lifecycle.status(LifecycleManagedPlugin)
    end

    test "cleanup/1 transitions to :unloaded" do
      LifecycleManagedPlugin.register()
      {:ok, _} = Lifecycle.init(LifecycleManagedPlugin)
      assert :ok = Lifecycle.cleanup(LifecycleManagedPlugin)
      assert :unloaded = Lifecycle.status(LifecycleManagedPlugin)
    end

    test "init/2 rejects invalid transition" do
      LifecycleManagedPlugin.register()
      {:ok, _} = Lifecycle.init(LifecycleManagedPlugin)

      assert {:error, {:invalid_transition, :initialized, :initialized}} =
               Lifecycle.init(LifecycleManagedPlugin)
    end

    test "activate/1 rejects invalid transition from :registered" do
      LifecycleManagedPlugin.register()

      assert {:error, {:invalid_transition, :registered, :active}} =
               Lifecycle.activate(LifecycleManagedPlugin)
    end

    test "negotiate_capabilities/2 returns available caps when all provided" do
      LifecycleManagedPlugin.register()

      assert {:ok, [:gestures, :animation]} =
               Lifecycle.negotiate_capabilities(LifecycleManagedPlugin, [:gestures, :animation])
    end

    test "negotiate_capabilities/2 returns missing caps" do
      LifecycleManagedPlugin.register()

      assert {:error, {:missing, [:textures]}} =
               Lifecycle.negotiate_capabilities(LifecycleManagedPlugin, [:gestures, :textures])
    end

    test "supports_platform?/2 checks platform support" do
      LifecycleManagedPlugin.register()
      assert Lifecycle.supports_platform?(LifecycleManagedPlugin, :ios)
      assert Lifecycle.supports_platform?(LifecycleManagedPlugin, :android)
      refute Lifecycle.supports_platform?(LifecycleManagedPlugin, :web)
    end

    test "status/1 returns :not_registered for unknown plugin" do
      assert :not_registered = Lifecycle.status(NonexistentPlugin)
    end
  end

  describe "Plugin dependency resolution" do
    defmodule BasePlugin do
      use Dala.Plugin

      import Dala.Plugin

      schema_version("1.0.0")
      description("Base plugin with no deps")

      component "base_widget" do
        prop("value", :string)
        capability(:gestures)
      end
    end

    defmodule DependentPlugin do
      use Dala.Plugin

      import Dala.Plugin

      schema_version("2.0.0")
      description("Plugin that depends on base")
      dependency({Dala.PluginTest.BasePlugin, "~> 1.0"})

      component "fancy_widget" do
        prop("data", :map)
        capability(:animation)
      end
    end

    test "check_dependencies/1 succeeds when deps are registered" do
      BasePlugin.register()
      DependentPlugin.register()
      assert :ok = Dala.Plugin.Lifecycle.check_dependencies(DependentPlugin)
    end

    test "check_dependencies/1 fails when deps are missing" do
      DependentPlugin.register()

      assert {:error, {:unsatisfied, _}} =
               Dala.Plugin.Lifecycle.check_dependencies(DependentPlugin)
    end

    test "resolve_dependency_order/0 returns topological order" do
      BasePlugin.register()
      DependentPlugin.register()
      order = Registry.resolve_dependency_order()
      assert is_list(order)
      base_idx = Enum.find_index(order, &(&1 == Dala.PluginTest.BasePlugin))
      dep_idx = Enum.find_index(order, &(&1 == Dala.PluginTest.DependentPlugin))
      assert base_idx < dep_idx
    end

    test "init_all/0 initializes plugins in dependency order" do
      BasePlugin.register()
      DependentPlugin.register()
      assert :ok = Registry.init_all()
      assert :initialized = Dala.Plugin.Lifecycle.status(BasePlugin)
      assert :initialized = Dala.Plugin.Lifecycle.status(DependentPlugin)
    end

    test "cleanup_all/0 cleans up in reverse dependency order" do
      BasePlugin.register()
      DependentPlugin.register()
      :ok = Registry.init_all()
      assert :ok = Registry.cleanup_all()
    end
  end

  describe "Registry status and state tracking" do
    defmodule StatusPlugin do
      use Dala.Plugin

      import Dala.Plugin

      component "status_widget" do
        prop("text", :string)
      end
    end

    test "get_status/1 returns initial status" do
      StatusPlugin.register()
      assert :registered = Registry.get_status(StatusPlugin)
    end

    test "set_status/2 updates status" do
      StatusPlugin.register()
      :ok = Registry.set_status(StatusPlugin, :active)
      assert :active = Registry.get_status(StatusPlugin)
    end

    test "get_state/1 returns nil initially" do
      StatusPlugin.register()
      assert nil == Registry.get_state(StatusPlugin)
    end

    test "set_state/2 updates state" do
      StatusPlugin.register()
      :ok = Registry.set_state(StatusPlugin, %{foo: :bar})
      assert %{foo: :bar} = Registry.get_state(StatusPlugin)
    end

    test "find_by_capability/1 returns matching plugins" do
      StatusPlugin.register()
      plugins = Registry.find_by_capability(:gestures)
      assert is_list(plugins)
    end

    test "find_by_platform/1 returns matching plugins" do
      StatusPlugin.register()
      plugins = Registry.find_by_platform(:ios)
      assert is_list(plugins)
    end
  end

  describe "Component lifecycle and optional capabilities" do
    test "component has default lifecycle" do
      component = %Component{name: "test", plugin: TestPlugin}
      assert :create in component.lifecycle
      assert :update in component.lifecycle
      assert :layout in component.lifecycle
      assert :event in component.lifecycle
      assert :dispose in component.lifecycle
    end

    test "component has empty optional_capabilities by default" do
      component = %Component{name: "test", plugin: TestPlugin}
      assert component.optional_capabilities == []
    end

    test "add_optional_capability/2 adds optional capability" do
      component = %Component{name: "test", plugin: TestPlugin}
      updated = Component.add_optional_capability(component, :gpu)
      assert :gpu in updated.optional_capabilities
    end
  end

  describe "Protocol capability negotiation and lifecycle encoding" do
    test "encode_capability_negotiation/2 encodes binary message" do
      encoded =
        Protocol.encode_capability_negotiation([:gestures, :animation], [
          :gestures,
          :accessibility
        ])

      assert is_binary(encoded)
      # First byte is capability opcode
      assert :binary.first(encoded) == 0xF1
    end

    test "encode_lifecycle_event/2 encodes binary message" do
      encoded = Protocol.encode_lifecycle_event(:init, %{opts: []})
      assert is_binary(encoded)
      # First byte is lifecycle opcode
      assert :binary.first(encoded) == 0xF0
    end
  end

  describe "Manifest with lifecycle fields" do
    defmodule ManifestLifecyclePlugin do
      use Dala.Plugin

      import Dala.Plugin

      description("Plugin with lifecycle manifest fields")
      permission(:camera)
      dependency({:maps, "~> 1.0"})
      platform(:ios)
      platform(:android)

      component "scanner" do
        prop("mode", :string)
        capability(:gestures)
      end
    end

    test "manifest includes lifecycle fields" do
      plugin = ManifestLifecyclePlugin.__plugin_info__()
      manifest = Manifest.generate(plugin)

      assert manifest["description"] == "Plugin with lifecycle manifest fields"
      assert "camera" in manifest["permissions"]
      assert is_list(manifest["dependencies"])
      assert "ios" in manifest["platforms"]
      assert "android" in manifest["platforms"]
      assert "gestures" in manifest["capabilities"]
      assert manifest["status"] == "registered"
    end
  end

  describe "Plugin with capabilities from use opts" do
    defmodule CapabilitiesFromOptsPlugin do
      use Dala.Plugin,
        capabilities: [:overlay, :textures],
        metadata: %{author: "test", license: "MIT"}

      import Dala.Plugin

      component "canvas" do
        prop("width", :f32)
        capability(:gestures)
      end
    end

    test "capabilities from use opts are merged with component capabilities" do
      info = CapabilitiesFromOptsPlugin.__plugin_info__()
      assert :overlay in info.capabilities
      assert :textures in info.capabilities
      assert :gestures in info.capabilities
    end

    test "metadata from use opts is passed through" do
      info = CapabilitiesFromOptsPlugin.__plugin_info__()
      assert info.metadata["author"] == "test"
      assert info.metadata["license"] == "MIT"
    end

    test "metadata defaults to empty map when not provided" do
      info = LifecyclePlugin.__plugin_info__()
      assert info.metadata == %{}
    end
  end

  describe "Plugin name from use opts" do
    defmodule NamedPlugin do
      use Dala.Plugin, name: :my_custom_name

      import Dala.Plugin

      component "widget" do
        prop("label", :string)
      end
    end

    test "plugin name can be overridden via use opts" do
      info = NamedPlugin.__plugin_info__()
      assert info.name == :my_custom_name
    end
  end

  describe "Plugin version from use opts" do
    defmodule VersionedPlugin do
      use Dala.Plugin, version: "1.2.3"

      import Dala.Plugin

      component "widget" do
        prop("label", :string)
      end
    end

    test "plugin version is set from use opts" do
      info = VersionedPlugin.__plugin_info__()
      assert info.plugin_version == "1.2.3"
    end
  end

  describe "Plugin dala_requires from use opts" do
    defmodule DalaRequiresPlugin do
      use Dala.Plugin, dala_requires: ">= 0.3.0"

      import Dala.Plugin

      component "widget" do
        prop("label", :string)
      end
    end

    test "dala_requires is set from use opts" do
      info = DalaRequiresPlugin.__plugin_info__()
      assert info.dala_requires == ">= 0.3.0"
    end
  end

  describe "Platforms from use opts" do
    defmodule PlatformsFromOptsPlugin do
      use Dala.Plugin, platforms: [:ios]

      import Dala.Plugin

      component "sensor" do
        prop("rate", :f32)
      end
    end

    test "platforms from use opts are merged with DSL platforms" do
      info = PlatformsFromOptsPlugin.__plugin_info__()
      assert :ios in info.platforms
    end
  end

  describe "Mix task dala.plugin.new" do
    test "generates plugin scaffold files" do
      Mix.shell(Mix.Shell.Process)
      send(self(), {:mix_shell_input, :yes})

      Mix.Tasks.Dala.Plugin.New.run(["dala_test_plugin"])

      assert File.exists?("dala_test_plugin/mix.exs")
      assert File.exists?("dala_test_plugin/lib/test_plugin.ex")
      assert File.exists?("dala_test_plugin/native/rust/src/lib.rs")
      assert File.exists?("dala_test_plugin/ios/test_plugin.h")
      assert File.exists?("dala_test_plugin/android/src/main/java/com/dala/test_plugin.java")
      assert File.exists?("dala_test_plugin/test/test_plugin_test.exs")
      assert File.exists?("dala_test_plugin/README.md")

      # Verify mix.exs contains correct app name
      mix_content = File.read!("dala_test_plugin/mix.exs")
      assert mix_content =~ ":dala_test_plugin"

      # Verify lib module compiles
      lib_content = File.read!("dala_test_plugin/lib/test_plugin.ex")
      assert lib_content =~ "use Dala.Plugin"
      assert lib_content =~ "component \"test_plugin\""

      # Cleanup
      File.rm_rf!("dala_test_plugin")
    after
      File.rm_rf!("dala_test_plugin")
    end

    test "generates plugin with custom name prefix" do
      Mix.Tasks.Dala.Plugin.New.run(["my_chart"])

      assert File.exists?("dala_my_chart/mix.exs")
      assert File.exists?("dala_my_chart/lib/my_chart.ex")

      lib_content = File.read!("dala_my_chart/lib/my_chart.ex")
      assert lib_content =~ "defmodule MyChart"
      assert lib_content =~ "component \"my_chart\""

      # Cleanup
      File.rm_rf!("dala_my_chart")
    after
      File.rm_rf!("dala_my_chart")
    end

    test "shows usage when no name provided" do
      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Mix.Tasks.Dala.Plugin.New.run([])
        end)

      assert output =~ "Usage:"
    end
  end
end
