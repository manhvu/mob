defmodule Dala.ML.CoreML do
  @moduledoc """
  CoreML integration for iOS.

  This module provides an Elixir API for using Apple's CoreML framework
  on iOS devices. CoreML is optimized by Apple and can use the Neural Engine
  for hardware-accelerated ML inference.

  ## Prerequisites

  - iOS device or simulator (CoreML is iOS-only)
  - CoreML model file (.mlmodel or .mlpackage)

  ## Converting models

  You can convert models from other formats to CoreML:

  1. **Axon → ONNX → CoreML**:
     ```elixir
     # Train with Axon
     model = Axon.input("input", shape: {nil, 784}) |> Axon.dense(10, activation: :softmax)
     {init_fn, predict_fn} = Axon.build(model)
     params = init_fn.(Nx.template({1, 784}, :f32), %{})

     # Export to ONNX (requires ortex or onnx package)
     # Then convert ONNX to CoreML using Apple's coremltools (Python)
     ```

  2. **Use pre-trained CoreML models** from Apple or third parties.

  ## Usage

      # Load a model
      :ok = Dala.ML.CoreML.load_model("/path/to/model.mlmodel", "my_model")

      # Check if loaded
      true = Dala.ML.CoreML.loaded?("my_model")

      # Make prediction
      {:ok, result_json} = Dala.ML.CoreML.predict("my_model", %{
        "input": [1.0, 2.0, 3.0]
      })

      # Unload when done
      :ok = Dala.ML.CoreML.unload_model("my_model")
  """

  @doc """
  Loads a CoreML model from the given path.

  ## Parameters

  - `model_path`: Path to the .mlmodel or .mlpackage file
  - `identifier`: A unique identifier for this model (used in later calls)

  ## Returns

  - `:ok` if successful
  - `{:error, reason}` if failed
  """
  def load_model(model_path, identifier) when is_binary(model_path) and is_binary(identifier) do
    try do
      case Dala.Native.coreml_load_model(model_path, identifier) do
        :ok -> :ok
        error -> {:error, error}
      end
    rescue
      UndefinedFunctionError -> :not_supported
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Unloads a previously loaded model.

  ## Parameters

  - `identifier`: The identifier used when loading the model
  """
  def unload_model(identifier) when is_binary(identifier) do
    Dala.Native.coreml_unload_model(identifier)
    :ok
  end

  @doc """
  Checks if a model is loaded.

  ## Parameters

  - `identifier`: The model identifier

  ## Returns

  `true` if the model is loaded, `false` otherwise.
  Returns `false` on non-iOS platforms.
  """
  def loaded?(identifier) when is_binary(identifier) do
    try do
      Dala.Native.coreml_is_model_loaded(identifier) == "true"
    rescue
      UndefinedFunctionError -> false
      _ -> false
    end
  end

  @doc """
  Makes a prediction using a loaded model.

  ## Parameters

  - `identifier`: The model identifier
  - `inputs`: A map of input names to values

  Input values can be:
  - Numbers (floats/integers)
  - Strings
  - Lists (converted to MLMultiArray)
  - Base64-encoded data (for large multi-array inputs)

  ## Returns

  `{:ok, result_json}` where `result_json` is a JSON string of the outputs.
  `{:error, reason}` if the prediction fails.
  `:not_supported` on non-iOS platforms.

  ## Example

      inputs = %{
        "input1" => 1.0,
        "input2" => [1.0, 2.0, 3.0]
      }

      case Dala.ML.CoreML.predict("my_model", inputs) do
        {:ok, json} ->
          result = Jason.decode!(json)
          # Use result...
        {:error, reason} ->
          # Handle error...
        :not_supported ->
          # CoreML not available
      end
  """
  def predict(identifier, inputs) when is_binary(identifier) and is_map(inputs) do
    try do
      inputs_json = Jason.encode!(inputs)
      Dala.Native.coreml_predict(identifier, inputs_json)
      :ok
    rescue
      UndefinedFunctionError -> :not_supported
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Lists all loaded model identifiers.

  ## Returns

  A list of model identifiers, or `:none` on non-iOS platforms.
  """
  def loaded_models do
    try do
      Dala.Native.coreml_loaded_models()
    rescue
      UndefinedFunctionError -> :none
      _ -> :none
    end
  end

  @doc """
  Convenience function to load and predict in one call.

  Note: Model must be loaded first using `load_model/2`.
  """
  def predict_with_loaded_model(identifier, inputs) do
    if loaded?(identifier) do
      predict(identifier, inputs)
    else
      {:error, "Model not loaded: #{identifier}"}
    end
  end
end
