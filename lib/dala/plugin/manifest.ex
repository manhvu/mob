defmodule Dala.Plugin.Manifest do
  @moduledoc """
  Generates native plugin manifests for iOS and Android platforms.

  The manifest describes to the native runtime which components are available
  and how to instantiate them. This enables dynamic plugin loading without
  recompiling the host application.

  ## Manifest Format

      {
        "schema_version": "1.0.0",
        "protocol_version": 3,
        "native_api_version": "2.0.0",
        "description": "Video playback plugin",
        "permissions": ["camera"],
        "dependencies": [{"name": "maps", "version": "~> 1.0"}],
        "platforms": ["ios", "android"],
        "capabilities": ["gestures", "accessibility", "animation"],
        "native_modules": {
          "ios": ["MyPlugin.IOS"],
          "android": ["MyPlugin.Android"]
        },
        "status": "registered",
        "components": {
          "video": {
            "ios": "DalaVideoView",
            "android": "com.dala.video.VideoView"
          }
        },
        "capabilities_by_component": {
          "video": ["gestures", "accessibility", "animation"]
        }
      }

  ## Usage

  Plugins can ship this manifest in their native resources:

  - iOS: `DalaPlugin.bundle/manifest.json`
  - Android: `assets/dala_plugins/my_plugin/manifest.json`

  The Dala runtime auto-discovers and registers plugins at startup.
  """

  alias Dala.Plugin

  @doc """
  Generates a manifest for the given plugin.

  The manifest is a JSON-compatible map that describes all components,
  their native class mappings, supported capabilities, and metadata.
  """
  @spec generate(Plugin.t()) :: map()
  def generate(plugin) do
    components =
      Enum.map(plugin.components, fn {_name, component} ->
        {component.name, component.natives}
      end)
      |> Map.new()

    capabilities =
      Enum.map(plugin.components, fn {name, component} ->
        {name, component.capabilities}
      end)
      |> Map.new()

    dependencies =
      Enum.map(plugin.dependencies, fn {name, version_req} ->
        %{"name" => to_string(name), "version" => version_req}
      end)

    native_modules =
      Enum.reduce(Map.to_list(plugin.native_modules), %{}, fn {platform, modules}, acc ->
        Map.put(acc, to_string(platform), Enum.map(modules, &to_string/1))
      end)

    plugin_version = if plugin.plugin_version, do: plugin.plugin_version, else: "0.0.0"

    events =
      Enum.map(plugin.events, fn {name, mod} ->
        %{
          "name" => Atom.to_string(name),
          "module" => to_string(mod)
        }
      end)

    %{
      "schema_version" => plugin.schema_version,
      "protocol_version" => plugin.protocol_version,
      "native_api_version" => plugin.native_api_version,
      "description" => plugin.description,
      "permissions" => Enum.map(plugin.permissions, &to_string/1),
      "dependencies" => dependencies,
      "platforms" => Enum.map(plugin.platforms, &to_string/1),
      "capabilities" => Enum.map(plugin.capabilities, &to_string/1),
      "native_modules" => native_modules,
      "status" => to_string(plugin.status),
      "components" => components,
      "capabilities_by_component" => capabilities,
      "plugin_version" => plugin_version,
      "events" => events,
      "dala_requires" => plugin.dala_requires,
      "metadata" => %{
        "plugin" => to_string(plugin.name),
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  @doc """
  Encodes the manifest as JSON.
  """
  @spec to_json(Plugin.t()) :: String.t()
  def to_json(plugin) do
    generate(plugin)
    |> Jason.encode!(pretty: true)
  end

  @doc """
  Writes the manifest to a file.
  """
  @spec write_to_file(Plugin.t(), String.t()) :: :ok | {:error, term()}
  def write_to_file(plugin, path) do
    json = to_json(plugin)

    case File.write(path, json) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads a manifest from JSON.
  """
  @spec from_json(String.t()) :: {:ok, map()} | {:error, term()}
  def from_json(json) do
    case Jason.decode(json) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Registers all components from a manifest with the runtime.

  This is used by the native host to dynamically register plugin
  components at startup.
  """
  @spec register_from_manifest(map()) :: :ok
  def register_from_manifest(manifest) do
    components = Map.get(manifest, "components", %{})

    capabilities =
      Map.get(manifest, "capabilities_by_component", Map.get(manifest, "capabilities", %{}))

    permissions = Map.get(manifest, "permissions", [])
    dependencies = Map.get(manifest, "dependencies", [])
    platforms = Map.get(manifest, "platforms", [])
    description = Map.get(manifest, "description")
    status = parse_status(Map.get(manifest, "status", "registered"))

    Enum.each(components, fn {component_name, native_mappings} ->
      plugin_name = String.to_atom("dynamic_" <> component_name)

      component = %Dala.Plugin.Component{
        name: component_name,
        plugin: plugin_name,
        natives: native_mappings,
        capabilities:
          case capabilities do
            m when is_map(m) -> Map.get(m, component_name, [])
            l when is_list(l) -> l
            _ -> []
          end
      }

      plugin = %Dala.Plugin{
        name: plugin_name,
        description: description,
        schema_version: Map.get(manifest, "schema_version", "1.0.0"),
        protocol_version: Map.get(manifest, "protocol_version", 3),
        native_api_version: Map.get(manifest, "native_api_version", "2.0.0"),
        components: %{component_name => component},
        permissions: Enum.map(permissions, &parse_atom/1),
        dependencies: parse_dependencies(dependencies),
        platforms: Enum.map(platforms, &parse_platform/1),
        capabilities:
          case capabilities do
            m when is_map(m) ->
              m |> Map.values() |> List.flatten() |> Enum.uniq()

            l when is_list(l) ->
              l

            _ ->
              []
          end,
        status: status,
        native_modules: %{}
      }

      Dala.Plugin.Registry.register(plugin)
    end)

    :ok
  end

  defp parse_status("registered"), do: :registered
  defp parse_status("initialized"), do: :initialized
  defp parse_status("active"), do: :active
  defp parse_status("error"), do: :error
  defp parse_status("unloaded"), do: :unloaded
  defp parse_status(_), do: :registered

  defp parse_atom(str) when is_binary(str), do: String.to_atom(str)
  defp parse_atom(atom) when is_atom(atom), do: atom

  defp parse_platform("ios"), do: :ios
  defp parse_platform("android"), do: :android
  defp parse_platform("web"), do: :web
  defp parse_platform(other), do: other

  defp parse_dependencies(deps) when is_list(deps) do
    Enum.map(deps, fn
      %{"name" => name, "version" => ver} ->
        {parse_atom(name), ver}

      other when is_map(other) ->
        name = Map.get(other, "name", :unknown)
        ver = Map.get(other, "version", "0.0.0")
        {parse_atom(name), ver}

      _ ->
        {:unknown, "0.0.0"}
    end)
  end

  defp parse_dependencies(_), do: []
end
