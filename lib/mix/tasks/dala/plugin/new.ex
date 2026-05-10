defmodule Mix.Tasks.Dala.Plugin.New do
  @moduledoc """
  Generates a new Dala plugin scaffold. Usage: mix dala.plugin.new dala_camera

  Creates a full plugin project structure with:
  - mix.exs (with dala dependency)
  - lib/ (with plugin module and component)
  - native/rust/src/lib.rs (NIF entry point)
  - ios/ (native bridge header)
  - android/ (native bridge stub)
  - test/ (test scaffold)
  - README.md
  """

  use Mix.Task

  @shortdoc "Generates a new Dala plugin scaffold"

  @impl true
  def run([name]) do
    app_name = name |> String.replace_prefix("dala_", "") |> String.replace(".", "_")
    mod_name = Macro.camelize(app_name)
    mod_prefix = if String.starts_with?(name, "dala_"), do: "Dala.#{mod_name}", else: mod_name
    snake = mod_name |> Macro.underscore() |> String.replace(~r/dala_/, "")

    Mix.shell().info("Creating plugin: #{name}")

    dirs = [
      "dala_#{app_name}",
      "dala_#{app_name}/lib",
      "dala_#{app_name}/native/rust/src",
      "dala_#{app_name}/ios",
      "dala_#{app_name}/android/src/main/java/com/dala",
      "dala_#{app_name}/test"
    ]

    Enum.each(dirs, &File.mkdir_p!/1)

    File.write!("dala_#{app_name}/mix.exs", mix_exs(name, mod_prefix))
    File.write!("dala_#{app_name}/lib/#{snake}.ex", lib_plugin(mod_prefix, mod_name, snake))
    File.write!("dala_#{app_name}/native/rust/src/lib.rs", rust_nif(app_name))
    File.write!("dala_#{app_name}/ios/#{snake}.h", ios_header(mod_prefix, mod_name))

    File.write!(
      "dala_#{app_name}/android/src/main/java/com/dala/#{snake}.java",
      android_java(mod_prefix, mod_name)
    )

    File.write!(
      "dala_#{app_name}/test/#{snake}_test.exs",
      test_scaffold(mod_prefix, mod_name, snake)
    )

    File.write!("dala_#{app_name}/README.md", readme(name, mod_prefix))

    Mix.shell().info("""
    Plugin #{name} created successfully!

    Generated files:
      dala_#{app_name}/mix.exs
      dala_#{app_name}/lib/#{snake}.ex
      dala_#{app_name}/native/rust/src/lib.rs
      dala_#{app_name}/ios/#{snake}.h
      dala_#{app_name}/android/src/main/java/com/dala/#{snake}.java
      dala_#{app_name}/test/#{snake}_test.exs
      dala_#{app_name}/README.md

    Next steps:
      cd dala_#{app_name}
      mix deps.get
      mix test
    """)
  end

  def run(_) do
    Mix.shell().error("Usage: mix dala.plugin.new <plugin_name>")
    Mix.shell().error("Example: mix dala.plugin.new dala_chart")
  end

  # ── Templates ──────────────────────────────────────────────────────────────

  defp mix_exs(name, mod_prefix) do
    """
    defmodule #{mod_prefix}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          version: "0.1.0",
          elixir: "~> 1.18",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          description: "#{mod_prefix} plugin for Dala",
          package: package()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          {:dala, path: "../.."}
        ]
      end

      defp package do
        [
          licenses: ["MIT"],
          links: %{"GitHub" => "https://github.com/your_org/#{name}"}
        ]
      end
    end
    """
  end

  defp lib_plugin(mod_prefix, mod_name, snake) do
    """
    defmodule #{mod_prefix} do
      use Dala.Plugin, name: #{inspect(String.to_atom(snake))}, metadata: %{author: "Your Name"}

      import Dala.Plugin

      description("#{mod_name} plugin for Dala")
      platform(:ios)
      platform(:android)

      component "#{snake}" do
        prop "enabled", :bool, default: true
        prop "value", :f32

        event "changed", payload: %{value: :f32}

        native "ios", "#{mod_prefix}.IOS"
        native "android", "com.dala.#{snake}.View"

        capability :gestures
        capability :accessibility
      end

      @impl true
      def init(_opts) do
        {:ok, %{}}
      end

      @impl true
      def handle_event(:changed, payload, state) do
        IO.inspect(payload, label: "#{mod_name} changed")
        {:ok, state}
      end

      @impl true
      def cleanup(_state) do
        :ok
      end
    end
    """
  end

  defp rust_nif(app_name) do
    snake = app_name |> Macro.underscore() |> String.replace(~r/dala_/, "")

    """
    use Rustler, otp_app: :#{String.to_atom(snake)}

    fn init(_env) -> bool {
        true
    }
    """
  end

  defp ios_header(mod_prefix, mod_name) do
    """
    #import <Foundation/Foundation.h>

    @interface #{mod_prefix}IOS : NSObject

    + (void)initialize;
    + (NSDictionary *)getProperties;
    + (void)setProperty:(NSString *)name value:(id)value;

    @end
    """
  end

  defp android_java(mod_prefix, mod_name) do
    """
    package com.dala.#{String.replace(mod_prefix, ".", "/")};

    import com.dala.runtime.DroidView;

    public class #{mod_name}View extends DroidView {
        // TODO: Implement native Android view
    }
    """
  end

  defp test_scaffold(mod_prefix, mod_name, snake) do
    """
    defmodule #{mod_prefix}Test do
      use ExUnit.Case
      alias Dala.Plugin.Registry

      setup do
        case Process.whereis(Dala.Plugin.Registry) do
          nil -> :ok
          pid -> GenServer.stop(pid)
        end
        Process.sleep(50)
        {:ok, _pid} = Registry.start_link()
        Registry.clear()
        :ok
      end

      test "#{mod_name} plugin info is valid" do
        info = #{mod_prefix}.__plugin_info__()
        assert info.description == "#{mod_name} plugin for Dala"
        assert :ios in info.platforms
        assert :android in info.platforms
      end

      test "#{mod_name} registers with the registry" do
        #{mod_prefix}.register()
        assert {:ok, _} = Registry.lookup_component("#{snake}")
      end

      test "component has expected props" do
        component = #{mod_prefix}.component("#{snake}")
        assert component != nil
        prop_names = Enum.map(component.props, & &1.name)
        assert "enabled" in prop_names
        assert "value" in prop_names
      end

      test "component has expected capabilities" do
        component = #{mod_prefix}.component("#{snake}")
        assert :gestures in component.capabilities
        assert :accessibility in component.capabilities
      end
    end
    """
  end

  defp readme(name, mod_prefix) do
    """
    # #{name}

    A Dala plugin for #{String.replace(name, "_", " ")}.

    ## Installation

    Add to your `mix.exs` dependencies:

        def deps do
          [{:#{name}, path: "dala_#{name}"}]
        end

    ## Usage

    Register the plugin in your app:

        #{mod_prefix}.register()

    Use the component in your screen:

        component "#{String.replace(name, "_", " ")}" do
          prop "enabled", :bool
        end
    """
  end
end
