defmodule Dala.ML do
  @moduledoc """
  Unified ML API for Dala apps on iOS and Android.

  Single entry point for machine learning in Dala, integrating:

  - **Nx** - Core tensor library (pure Elixir, works everywhere)
  - **Scholar** - Traditional ML (regression, clustering, SVM, etc.)
  - **NxSignal** - Digital signal processing (audio, time series)
  - **Axon** - Neural networks (deep learning)
  - **EMLX** - Apple Silicon GPU acceleration (iOS only, auto-configured)
  - **CoreML** - iOS-native ML framework (Neural Engine, iOS only)
  - **ONNX Runtime** - Cross-platform inference engine (iOS/Android)

  ## Quick Start

      # Zero-config setup (call once at app startup)
      Dala.ML.setup()

      # Now use any of the integrated libraries
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      Nx.sum(tensor)

  ## Platform Support

  | Library | iOS Device | iOS Sim | Android |
  |---------|-----------|--------|---------|
  | Nx | ✅ | ✅ | ✅ |
  | Scholar | ✅ | ✅ | ✅ |
  | NxSignal | ✅ | ✅ | ✅ |
  | Axon | ✅ | ✅ | ✅ |
  | EMLX (GPU) | ✅ | ✅ | ❌ |
  | CoreML | ✅ | ✅ | ❌ |
  | ONNX Runtime | ✅ | ✅ | ✅ |
  """

  @doc """
  Sets up the ML stack for the current platform.

  Call once at app startup. Detects platform and configures the best
  available backend automatically.
  """
  @spec setup() :: :ok
  def setup do
    cond do
      ios?() ->
        Dala.ML.EMLX.setup()

      android?() ->
        Nx.default_backend(Nx.BinaryBackend)
        :ok

      true ->
        Nx.default_backend(Nx.BinaryBackend)
        :ok
    end
  end

  @doc """
  Returns `true` if running on any iOS platform (device or simulator).
  """
  @spec ios?() :: boolean()
  def ios? do
    Dala.Platform.Native.platform() == :ios
  rescue
    _ -> false
  end

  @doc """
  Returns `true` if running on a real iOS device (not simulator).
  """
  @spec ios_device?() :: boolean()
  def ios_device? do
    Dala.ML.EMLX.ios_device?()
  end

  @doc """
  Returns `true` if running in iOS Simulator.
  """
  @spec ios_simulator?() :: boolean()
  def ios_simulator? do
    Dala.ML.EMLX.ios_simulator?()
  end

  @doc """
  Returns `true` if running on Android.
  """
  @spec android?() :: boolean()
  def android? do
    Dala.Platform.Native.platform() == :android
  rescue
    _ -> false
  end

  @doc """
  Gets the current ML stack status.
  """
  @spec status() :: map()
  def status do
    platform =
      cond do
        ios_device?() -> :ios_device
        ios_simulator?() -> :ios_simulator
        android?() -> :android
        true -> :other
      end

    %{
      platform: platform,
      backend: Dala.Ml.Nx.default_backend(),
      emlx_available: Dala.ML.EMLX.available?(),
      coreml_available:
        ios?() and Code.ensure_loaded?(Dala.Native) and
          function_exported?(Dala.Native, :coreml_load_model, 2),
      onnx_available: Dala.ML.ONNX.available?(),
      libraries: %{
        nx: Code.ensure_loaded?(Nx),
        scholar: Code.ensure_loaded?(Scholar),
        nx_signal: Code.ensure_loaded?(NxSignal),
        axon: Code.ensure_loaded?(Axon),
        emlx: Code.ensure_loaded?(EMLX)
      }
    }
  end

  @doc """
  Quick verification that the ML stack is working.
  """
  @spec verify() :: map()
  def verify do
    tensor = Nx.tensor([1.0, 2.0, 3.0])
    sum = Nx.sum(tensor) |> Nx.to_number()
    %{status: :ok, sum: sum, backend: Dala.Ml.Nx.default_backend()}
  rescue
    e -> %{status: :error, message: Exception.message(e)}
  end

  @doc """
  Returns a list of available ML backends for the current platform.
  """
  @spec available_backends() :: [atom()]
  def available_backends do
    backends = [:nx]

    backends =
      if Dala.ML.EMLX.available?() do
        [:emlx | backends]
      else
        backends
      end

    backends =
      if ios?() and Code.ensure_loaded?(Dala.Native) and
           function_exported?(Dala.Native, :coreml_load_model, 2) do
        [:coreml | backends]
      else
        backends
      end

    backends =
      if Dala.ML.ONNX.available?() do
        [:onnx | backends]
      else
        backends
      end

    Enum.reverse(backends)
  end

  @doc """
  Benchmarks a simple ML operation on the current backend.

  Returns `%{time_ms: float, backend: term, gflops: float}`.
  """
  @spec benchmark(keyword()) :: map()
  def benchmark(opts \\ []) do
    size = Keyword.get(opts, :size, 100)
    iterations = Keyword.get(opts, :iterations, 10)

    setup()

    key = Nx.Random.key(42)
    {a, _} = Nx.Random.uniform(key, shape: {size, size})
    {b, _} = Nx.Random.uniform(key, shape: {size, size})

    # Warmup
    Nx.dot(a, b) |> Nx.to_binary()

    {total_us, _} =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          Nx.dot(a, b) |> Nx.to_binary()
        end
      end)

    avg_ms = total_us / iterations / 1000
    ops = 2 * size * size * size
    gflops = ops / (avg_ms / 1000) / 1.0e9

    %{
      time_ms: Float.round(avg_ms, 3),
      backend: Nx.default_backend(),
      gflops: Float.round(gflops, 3),
      matrix_size: size,
      iterations: iterations
    }
  end

  @doc """
  Runs inference using the best available backend.

  Dispatches based on model type:
  - Binary (string) on iOS → CoreML
  - Integer → ONNX session
  - Tuple → Axon model
  """
  @spec predict(term(), term()) :: {:ok, term()} | {:error, term()}
  def predict(model, input) do
    cond do
      is_binary(model) and ios?() ->
        Dala.ML.CoreML.predict(model, input)

      is_integer(model) ->
        Dala.ML.ONNX.run(model, input)

      is_tuple(model) ->
        Dala.Ml.Nx.inference(elem(model, 0), elem(model, 1), input)

      true ->
        {:error, "Unsupported model type: #{inspect(model)}"}
    end
  end
end
