defmodule Dala.ML.ConfigHelper do
  @moduledoc """
  Helper to configure ML dependencies and settings for Dala apps.

  ## Usage:

      # In your app's mix.exs:
      defp deps do
        [
          {:dala, "~> 0.3"},
          {:nx, "~> 0.10"},
          {:axon, "~> 0.8.0"},
          {:scholar, "~> 0.4.0"},
          {:nx_signal, "~> 0.3.0"},
          {:polaris, "~> 0.1"}
          # Optional: Apple Silicon GPU
          {:emlx, github: "elixir-nx/emlx", branch: "main"}
        ]
      end

  ## Quantized Models:

      # Download pre-trained quantized models:
      # - dalaileNetV2: https://huggingface.co/onnx/models/tree/main/vision/classification/dalailenet/model/unknown/1
      # - YOLO Nano: https://github.com/ultralytics/yolov5/releases

      # Configure in your app:
      config = Dala.ML.ConfigHelper.quantized_model_config()
      # => %{models: [...], note: "Download from HuggingFace..."}
  """

  @doc """
  Returns the recommended deps for ML on Dala.

  Add these to your app's mix.exs deps/0 function.

  ## Optional deps

  - `{:emlx, github: "elixir-nx/emlx", branch: "main"}` — Apple Silicon GPU (iOS/macOS)
  - `{:axon_onnx, "~> 0.5"}` — ONNX model loading for Axon
  """
  @spec recommended_deps() :: [{atom(), String.t() | keyword()}]
  def recommended_deps do
    [
      {:nx, "~> 0.10"},
      {:axon, "~> 0.8.0"},
      {:scholar, "~> 0.4.0"},
      {:nx_signal, "~> 0.3.0"},
      {:polaris, "~> 0.1"}
    ]
  end

  @doc """
  Returns quantized model configuration for iOS.

  ## Available Models:

  - **dalaileNetV2 Quantized**: 224x224, 1000 classes, int8, 14MB
  - **YOLO Nano Quantized**: 416x416, [batch, grid, grid, 3*(5+classes)], int4, 6MB

  ## Download:
  Pre-trained models are available from HuggingFace or TensorFlow Hub.
  """
  @spec quantized_model_config() :: map()
  def quantized_model_config do
    %{
      models: [
        %{
          name: "dalailenet_v2_quantized",
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
  @spec recommended_config() :: String.t()
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
  @spec build_env_vars() :: %{String.t() => String.t()}
  def build_env_vars do
    %{
      "LIBMLX_ENABLE_JIT" => "false",
      "LIBMLX_VERSION" => "0.31.2"
    }
  end

  @doc """
  Prints a copy-pasteable mix.exs snippet.
  """
  @spec print_mix_deps() :: String.t()
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
  @spec print_config() :: String.t()
  def print_config do
    recommended_config()
  end
end
