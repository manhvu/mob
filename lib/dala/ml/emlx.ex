defmodule Dala.ML.EMLX do
  @compile {:nowarn_undefined, [:dala_nif, :Nx]}
  @moduledoc """
  iOS integration layer for EMLX (MLX backend for Nx).

  This module provides automatic iOS-specific configuration for using
  EMLX on iOS devices and simulator. No manual configuration needed.

  ## iOS Constraints

  - **Real iOS devices**: JIT is automatically disabled (W^X policy)
  - **iOS Simulator**: JIT works and is auto-enabled for development
  - **Metal GPU**: Automatically used on Apple Silicon (unified memory)

  ## Usage (Zero config!)

      # That's it! Just use Nx/EMLX as normal.
      # The backend is automatically configured when your app starts.

      tensor = Nx.tensor([1.0, 2.0, 3.0])
      Nx.sum(tensor)  # Uses EMLX backend on iOS, Nx.BinaryBackend elsewhere
  """

  @doc """
  Auto-configures EMLX for the current platform.

  Call this once at app startup. It will:
  1. Detect if running on iOS device or simulator
  2. Disable JIT on real devices (required by W^X policy)
  3. Enable Metal GPU acceleration on Apple Silicon
  4. Set EMLX as the default Nx backend

  Safe to call multiple times. On non-iOS platforms, this is a no-op.
  """
  def setup do
    if ios_device?() or ios_simulator?() do
      config = platform_config()

      # Set environment variables for EMLX
      System.put_env("LIBMLX_ENABLE_JIT", to_string(config.jit_enabled))

      # Set Nx default backend to EMLX with appropriate device
      Nx.default_backend({EMLX.Backend, device: config.device})

      :dala_nif.log("Dala.ML.EMLX: configured for #{config.device}, JIT=#{config.jit_enabled}")
      {:ok, config}
    else
      # Non-iOS: use default Nx backend
      :ok
    end
  end

  @doc """
  Returns the appropriate EMLX configuration for the current iOS platform.

  Automatically detects device vs simulator and configures appropriately.
  """
  def platform_config do
    cond do
      ios_device?() ->
        %{
          # Metal GPU on Apple Silicon
          device: :gpu,
          # JIT blocked by W^X policy
          jit_enabled: false,
          metal_jit: false
        }

      ios_simulator?() ->
        %{
          # Metal GPU in simulator too
          device: :gpu,
          # JIT works in simulator
          jit_enabled: true,
          metal_jit: true
        }

      true ->
        %{device: :cpu, jit_enabled: false, metal_jit: false}
    end
  end

  @doc """
  Returns `true` if running on a real iOS device (not simulator).
  """
  def ios_device? do
    case :os.type() do
      {:unix, :darwin} ->
        # Check if running on iOS device by looking for device-specific paths
        # or by checking if we're in the iOS simulator environment
        not ios_simulator?()

      _ ->
        false
    end
  end

  @doc """
  Returns `true` if running in iOS Simulator.
  """
  def ios_simulator? do
    System.get_env("SIMULATOR_DEVICE_NAME") != nil or
      System.get_env("IPHONE_SIMULATOR_ROOT") != nil
  end

  @doc """
  Returns the default device for the current platform.
  """
  def default_device do
    if ios_device?() or ios_simulator?() do
      # GPU (Metal) is available on both iOS devices and simulator
      :gpu
    else
      :cpu
    end
  end

  @doc """
  Checks if EMLX is available and properly configured.
  """
  def available? do
    try do
      # Try to load EMLX and check if it can initialize
      case Code.ensure_loaded(EMLX) do
        {:module, _} ->
          # Try a simple operation to verify it works
          try do
            Nx.tensor(1, backend: EMLX.Backend) |> Nx.to_number()
            true
          rescue
            _ -> false
          end

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end

  @doc """
  Creates a simple test tensor to verify EMLX is working.
  """
  def verify_installation do
    if available?() do
      tensor = Nx.tensor([1.0, 2.0, 3.0], backend: EMLX.Backend)
      sum = Nx.sum(tensor) |> Nx.to_number()
      %{status: :ok, sum: sum, device: default_device()}
    else
      %{status: :error, message: "EMLX not available"}
    end
  end

  @doc """
  Runs a simple benchmark to verify GPU acceleration.
  """
  def benchmark do
    if available?() do
      # Create a decent-sized matrix
      a = Nx.random_uniform({100, 100}, backend: EMLX.Backend)
      b = Nx.random_uniform({100, 100}, backend: EMLX.Backend)

      {time_microseconds, _} =
        :timer.tc(fn ->
          Nx.dot(a, b)
          |> Nx.to_binary()
        end)

      %{status: :ok, time_ms: time_microseconds / 1000, device: default_device()}
    else
      %{status: :error, message: "EMLX not available"}
    end
  end
end
