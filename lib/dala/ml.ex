defmodule Dala.ML do
  @moduledoc """
  Unified ML API for Dala apps on iOS and Android.

  This module provides a single entry point for machine learning in Dala,
  integrating the full Nx ecosystem and iOS-native CoreML:

  - **Nx** - Core tensor library (pure Elixir, works everywhere)
  - **Scholar** - Traditional ML (regression, clustering, SVM, etc.)
  - **NxSignal** - Digital signal processing (audio, time series)
  - **Axon** - Neural networks (deep learning)
  - **EMLX** - Apple Silicon GPU acceleration (iOS only, auto-configured)
  - **CoreML** - iOS-native ML framework (Neural Engine, iOS only)
  - **ONNX Runtime** - Cross-platform inference engine (iOS/Android/desktop)

  ## Quick Start

      # Zero-config setup (call once at app startup)
      Dala.ML.setup()

      # Now use any of the integrated libraries
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      Nx.sum(tensor)

  ## Platform Support

  | Library | iOS Device | iOS Sim | Android | macOS | Linux |
  |---------|-----------|--------|---------|-------|-------|
  | Nx | ✅ | ✅ | ✅ | ✅ | ✅ |
  | Scholar | ✅ | ✅ | ✅ | ✅ | ✅ |
  | NxSignal | ✅ | ✅ | ✅ | ✅ | ✅ |
  | Axon | ✅ | ✅ | ✅ | ✅ | ✅ |
  | EMLX (GPU) | ✅ | ✅ | ❌ | ✅ | ❌ |
  | CoreML | ✅ | ✅ | ❌ | ❌ | ❌ |
  | ONNX Runtime | ✅ | ✅ | ✅ | ✅ | ✅ |

  ## Not Supported on Mobile

  - **EXLA/XLA** - Requires precompiled XLA binaries (x86_64 Linux/macOS only)
  - **NxIREE** - Requires IREE runtime (no iOS/Android support)

  ## ONNX Runtime (Cross-Platform)

  For best cross-platform performance, use ONNX Runtime:

      # Create session from ONNX model
      {:ok, session_id} = Dala.ML.ONNX.create_session(model_data)

      # Run inference
      {:ok, output} = Dala.ML.ONNX.run(session_id, input_binary)
  """

  # No alias - we want to use the actual Nx tensor library
  # Dala.ML.Nx is available via Dala.ML.Nx

  @doc """
  Sets up the ML stack for the current platform.

  Call this once at app startup. It will:
  1. Detect the platform (iOS device, iOS sim, Android, etc.)
  2. Configure the best available Nx backend
  3. Enable EMLX GPU acceleration on iOS (if available)
  4. Return the configuration used

  ## Examples

      # In your app's start function:
      def start(_type, _args) do
        Dala.ML.setup()
        # ... rest of app startup
      end

      # Or in a screen's mount:
      def mount(_params, _session, socket) do
        Dala.ML.setup()
        {:ok, socket}
      end
  """
  def setup do
    cond do
      ios?() -> Dala.ML.EMLX.setup()
      true -> Dala.ML.Nx.init_for_ios()
    end
  end

  @doc """
  Returns `true` if running on any iOS platform (device or simulator).
  """
  def ios? do
    try do
      Dala.Native.platform() == :ios
    rescue
      _ -> false
    end
  end

  @doc """
  Returns `true` if running on a real iOS device (not simulator).
  """
  def ios_device? do
    Dala.ML.EMLX.ios_device?()
  end

  @doc """
  Returns `true` if running in iOS Simulator.
  """
  def ios_simulator? do
    Dala.ML.EMLX.ios_simulator?()
  end

  @doc """
  Returns `true` if running on Android.
  """
  def android? do
    try do
      Dala.Native.platform() == :android
    rescue
      _ -> false
    end
  end

  @doc """
  Gets the current ML stack status.

  Returns a map with:
  - `:platform` - :ios_device, :ios_simulator, :android, or :other
  - `:backend` - configured Nx backend
  - `:emlx_available` - if EMLX is available
  - `:coreml_available` - if CoreML is available (iOS only)
  - `:libraries` - which ML libraries are loaded
  """
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
      backend: Dala.ML.Nx.default_backend(),
      emlx_available: Dala.ML.EMLX.available?(),
      coreml_available: ios?(),
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

  Runs a simple tensor operation and returns the result.
  """
  def verify do
    try do
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      sum = Nx.sum(tensor) |> Nx.to_number()
      %{status: :ok, sum: sum, backend: Dala.ML.Nx.default_backend()}
    rescue
      e -> %{status: :error, message: Exception.message(e)}
    end
  end
end
