defmodule Mob.ML.EMLX do
  @moduledoc """
  iOS integration layer for EMLX (MLX backend for Nx).

  This module provides iOS-specific configuration and helpers for using
  EMLX on iOS devices and simulator.

  ## iOS Constraints

  - **Real iOS devices**: JIT is blocked by W^X policy. Set `LIBMLX_ENABLE_JIT=false`
    (default) and use `--disable-jit` BEAM flag.
  - **iOS Simulator**: JIT works; can enable with `LIBMLX_ENABLE_JIT=true`.
  - **Metal GPU**: Available on both devices and simulator with unified memory.

  ## Usage

      # In your Mob app's config/config.exs:
      config :nx, :default_backend, {EMLX.Backend, device: :cpu}

      # For GPU (Metal):
      config :nx, :default_backend, {EMLX.Backend, device: :gpu}

      # Disable JIT for iOS device builds:
      config :emlx, :jit_enabled, false
  """

  @doc """
  Returns the appropriate EMLX configuration for the current iOS platform.

  Detects whether running on iOS device or simulator and configures
  EMLX accordingly.
  """
  def platform_config do
    if ios_device?() do
      %{
        device: default_device(),
        jit_enabled: false,
        metal_jit: false
      }
    else
      # iOS Simulator
      %{
        device: default_device(),
        jit_enabled: System.get_env("LIBMLX_ENABLE_JIT", "false") == "true",
        metal_jit: System.get_env("LIBMLX_ENABLE_JIT", "false") == "true"
      }
    end
  end

  @doc """
  Sets up EMLX for iOS by configuring environment variables before loading.

  Call this early in your app startup (before any Nx/EMLX calls).
  """
  def setup_for_ios do
    config = platform_config()

    unless config.jit_enabled do
      # Ensure JIT is disabled for iOS devices
      System.put_env("LIBMLX_ENABLE_JIT", "false")
    end

    # Set default device
    Nx.default_backend({EMLX.Backend, device: config.device})

    :ok
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
