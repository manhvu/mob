defmodule Dala.ML.Nx do
  @moduledoc """
  Nx integration helpers for Dala on iOS.

  Nx itself is pure Elixir and works on any platform. This module provides
  iOS-specific helpers and backend selection logic.
  """

  @doc """
  Initializes Nx with the best available backend for iOS.

  Priority:
  1. EMLX (if available) - best for Apple Silicon
  2. Nx default (pure Elixir fallback)
  """
  def init_for_ios do
    cond do
      emlx_available?() ->
        Dala.ML.EMLX.setup_for_ios()
        :emlx

      true ->
        # Pure Nx (CPU-only, no acceleration)
        Nx.default_backend(Nx.BinaryBackend)
        :nx_binary
    end
  end

  @doc """
  Checks if EMLX is available.
  """
  def emlx_available? do
    try do
      Code.ensure_loaded?(EMLX)
    rescue
      _ -> false
    end
  end

  @doc """
  Creates a tensor on iOS with platform-appropriate backend.
  """
  def tensor(data, opts \\ []) do
    backend = Keyword.get(opts, :backend, default_backend())
    Nx.tensor(data, Keyword.put(opts, :backend, backend))
  end

  @doc """
  Returns the default backend for the current iOS platform.
  """
  def default_backend do
    if emlx_available?() do
      {EMLX.Backend, device: Dala.ML.EMLX.default_device()}
    else
      Nx.BinaryBackend
    end
  end

  @doc """
  Example: Simple neural network layer using Axon on iOS.

  Note: Axon is pure Elixir and works on any platform with Nx.
  This is just an example - Axon needs to be added as a dependency.
  """
  def example_dense_layer do
    # This is an example - requires Axon as a dependency
    quote do
      require Axon

      Axon.input("input", shape: {nil, 784})
      |> Axon.dense(128, activation: :relu)
      |> Axon.dense(10, activation: :softmax)
    end
  end

  @doc """
  Loads a pre-trained model for inference on iOS.

  Note: This is a placeholder. In practice, you would:
  1. Train or download a pre-trained model
  2. Serialize it (Axon supports serialization)
  3. Load it here for inference
  """
  def load_model(_model_path) do
    # Placeholder for model loading logic
    # Example:
    # {:ok, model} = Axon.load("path/to/model.axmodel")
    :not_implemented
  end

  @doc """
  Runs inference with a model using the best available backend.
  """
  def inference(model, input_data) do
    backend = default_backend()
    input_tensor = tensor(input_data, backend: backend)
    # Axon.predict(model, params, input_tensor)
    {:ok, input_tensor}
  end
end
