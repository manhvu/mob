defmodule Dala.ML.ONNX do
  @moduledoc """
  ONNX Runtime integration for cross-platform ML inference.

  This module provides an Elixir API for using ONNX Runtime,
  which can leverage platform-specific execution providers:

  - **iOS**: CoreML EP (Apple Neural Engine)
  - **Android**: NNAPI EP (Android Neural Networks API)
  - **Fallback**: CPU EP (works everywhere)

  ## Prerequisites

  - ONNX model file (.onnx)
  - ONNX Runtime library for your platform

  ## Converting models to ONNX

  You can convert models from other formats:

      # From Axon (via Elixir)
      {init_fn, predict_fn} = Axon.build(model)
      params = init_fn.(Nx.template({1, 784}, :f32), %{})

      # Export to ONNX (requires ortex or similar)
      # Then use ONNX Runtime for inference

  ## Usage

      # Create session from ONNX model
      {:ok, session_id} = Dala.ML.ONNX.create_session(model_data)

      # Run inference
      {:ok, output_binary} = Dala.ML.ONNX.run(session_id, input_binary)

      # Convert output to Nx tensor
      output = Nx.from_binary(output_binary, {:f32, shape})

      # Clean up when done
      :ok = Dala.ML.ONNX.destroy_session(session_id)
  """

  @doc """
  Creates an ONNX session from model data.

  ## Parameters

  - `model_data`: Binary ONNX model data (from file or memory)

  ## Returns

  `{:ok, session_id}` on success
  `:not_supported` on unsupported platforms
  `:error` on failure
  """
  def create_session(model_data) when is_binary(model_data) do
    try do
      case Dala.Native.onnx_create_session(model_data) do
        :not_supported -> :not_supported
        :error -> :error
        {:ok, session_id} -> {:ok, session_id}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
      end
    rescue
      UndefinedFunctionError -> :not_supported
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Destroys an ONNX session and frees resources.
  """
  def destroy_session(session_id) when is_integer(session_id) do
    try do
      case Dala.Native.onnx_destroy_session(session_id) do
        :ok -> :ok
        :error -> :error
        _other -> :error
      end
    rescue
      UndefinedFunctionError -> :ok
      _ -> :ok
    end
  end

  @doc """
  Runs inference on an ONNX session.

  ## Parameters

  - `session_id`: Session ID from `create_session/1`
  - `input`: Binary input data (Nx tensor serialized to binary)

  ## Returns

  `{:ok, output_binary}` on success
  `:not_supported` on unsupported platforms
  `:error` on failure
  """
  def run(session_id, input) when is_integer(session_id) and is_binary(input) do
    try do
      case Dala.Native.onnx_run(session_id, input) do
        :not_supported -> :not_supported
        {:ok, output} -> {:ok, output}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
      end
    rescue
      UndefinedFunctionError -> :not_supported
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Convenience function: Load model from file and create session.
  """
  def load_model_from_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, model_data} -> create_session(model_data)
      {:error, reason} -> {:error, "Failed to read model file: #{reason}"}
    end
  end

  @doc """
  Checks if ONNX Runtime is available on this platform.
  """
  def available? do
    try do
      # Try a dummy call to check if NIF is loaded
      Dala.Native.onnx_create_session(<<>>)
      true
    rescue
      UndefinedFunctionError -> false
      _ -> false
    end
  end
end
