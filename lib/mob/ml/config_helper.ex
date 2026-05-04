defmodule Mob.ML.ConfigHelper do
  @moduledoc """
  Helper to configure EMLX dependencies and settings for Mob iOS apps.

  Use this module to generate the correct configuration for your app's mix.exs.
  """

  @doc """
  Returns the recommended deps for EMLX on iOS.

  Add these to your app's mix.exs deps/0 function.
  """
  def recommended_deps do
    [
      {:nx, github: "elixir-nx/nx", sparse: "nx"},
      {:axon, "~> 0.6"},
      {:emlx, github: "elixir-nx/emlx", branch: "main"},
      # Optional: for model loading/serialization
      {:axon_onnx, "~> 0.4", optional: true}
    ]
  end

  @doc """
  Returns quantized model configuration for iOS.

  Use this to configure pre-trained quantized models.
  """
  def quantized_model_config do
    %{
      models: [
        %{
          name: "mobilenet_v2_quantized",
          input_size: {224, 224, 3},
          output_classes: 1000,
          quantization: "int8",
          size_mb: 14
        },
        %{
          name: "yolo_nano_quantized",
          input_size: {416, 416, 3},
          output_format: "[batch, grid, grid, 3 * (5 + classes)]",
          quantization: "int4",
          size_mb: 6
        }
      ],
      note: "Download pre-trained models from HuggingFace or TensorFlow Hub"
    }
  end

  @doc """
  Returns the recommended config for EMLX on iOS.

  Add this to your app's config/config.exs.
  """
  def recommended_config do
    """
    # Disable JIT for iOS devices (W^X policy blocks it)
    config :emlx, jit_enabled: false

    # Use EMLX as the default Nx backend
    # Options: device: :gpu (Metal) or device: :cpu
    config :nx, :default_backend, {EMLX.Backend, device: :gpu}

    # Optional: Set MLX version
    # config :emlx, :mlx_version, "0.31.2"
    """
  end

  @doc """
  Returns environment variables for iOS builds.

  Add these to your build script or mix.exs make_env.
  """
  def build_env_vars do
    %{
      "LIBMLX_ENABLE_JIT" => "false",
      "LIBMLX_VERSION" => "0.31.2"
    }
  end

  @doc """
  Prints a copy-pasteable mix.exs snippet.
  """
  def print_mix_deps do
    deps = recommended_deps()

    snippet =
      deps
      |> Enum.map(fn dep ->
        case dep do
          {name, opts} when is_list(opts) ->
            "{#{inspect(name)}, #{inspect(opts)}}"

          {name, version} ->
            "{#{inspect(name)}, #{inspect(version)}}"
        end
      end)
      |> Enum.join(",\n  ")

    """
    defp deps do
      [
        # ... your other deps ...
        #{snippet}
      ]
    end
    """
  end

  @doc """
  Prints a copy-pasteable config.exs snippet.
  """
  def print_config do
    recommended_config()
  end
end
