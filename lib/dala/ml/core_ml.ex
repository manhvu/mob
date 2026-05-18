defmodule Dala.ML.CoreML do
  @moduledoc """
  CoreML integration for iOS.

  Provides an Elixir API for Apple's CoreML framework via NIF calls.
  CoreML uses the Apple Neural Engine (ANE) for hardware-accelerated
  ML inference on iOS devices and simulators.

  All NIF functions run on the dirty CPU scheduler.

  ## Prerequisites

  - iOS device or simulator
  - CoreML model file (.mlmodel or .mlpackage)

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
  - `identifier`: A unique identifier for this model

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  - `:not_supported` on non-iOS platforms
  """
  @spec load_model(String.t(), String.t()) :: :ok | {:error, term()} | :not_supported
  def load_model(model_path, identifier)
      when is_binary(model_path) and is_binary(identifier) do
    Dala.Native.coreml_load_model(model_path, identifier)
  end

  @doc """
  Unloads a previously loaded model.
  """
  @spec unload_model(String.t()) :: :ok | :not_supported
  def unload_model(identifier) when is_binary(identifier) do
    Dala.Native.coreml_unload_model(identifier)
  end

  @doc """
  Checks if a model is loaded.

  Returns `true` if loaded, `false` otherwise.
  Returns `false` on non-iOS platforms.
  """
  @spec loaded?(String.t()) :: boolean()
  def loaded?(identifier) when is_binary(identifier) do
    Dala.Native.coreml_is_model_loaded(identifier)
  end

  @doc """
  Makes a prediction using a loaded model.

  ## Parameters

  - `identifier`: The model identifier
  - `inputs`: A map of input names to values (numbers, strings, lists)

  ## Returns

  - `{:ok, result_json}` on success
  - `{:error, reason}` on failure
  - `:not_supported` on non-iOS platforms
  """
  @spec predict(String.t(), map()) :: {:ok, String.t()} | {:error, term()} | :not_supported
  def predict(identifier, inputs) when is_binary(identifier) and is_map(inputs) do
    inputs_json = Jason.encode!(inputs)
    Dala.Native.coreml_predict(identifier, inputs_json)
  end

  @doc """
  Lists all loaded model identifiers.
  """
  @spec loaded_models() :: [String.t()]
  def loaded_models do
    Dala.Native.coreml_loaded_models()
  end

  @doc """
  Run prediction on an already-loaded model.

  Unlike `load_model/2` + `predict/2`, this does NOT load the model.
  The model must be loaded first via `load_model/2`.
  """
  @spec predict_with_loaded_model(String.t(), map()) ::
          {:ok, String.t()} | {:error, term()} | :not_supported
  def predict_with_loaded_model(identifier, inputs)
      when is_binary(identifier) and is_map(inputs) do
    if loaded?(identifier) do
      predict(identifier, inputs)
    else
      {:error, "Model not loaded: #{identifier}"}
    end
  end
end
