defmodule Dala.ML.EMLX do
  @moduledoc """
  EMLX (Apple Silicon GPU) integration for Dala.

  EMLX provides GPU-accelerated tensor operations via Apple's Metal framework.
  This module handles zero-config setup: no NIF delegation needed, just
  direct Application config and Nx backend selection.

  ## Platform Behavior

  | Platform | GPU | JIT | Backend |
  |----------|-----|-----|---------|
  | iOS device | Metal (`:gpu`) | Disabled (W^X) | `{EMLX.Backend, device: :gpu}` |
  | iOS simulator | Metal (`:gpu`) | Enabled | `{EMLX.Backend, device: :gpu}` |
  | Other | N/A | N/A | `Nx.BinaryBackend` |

  ## Usage

      # At app startup — auto-configures everything:
      Dala.ML.setup()

      # Or configure EMLX directly:
      Dala.ML.EMLX.setup()
  """

  @doc """
  Checks if the EMLX hex package is available at runtime.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(EMLX) and Code.ensure_loaded?(EMLX.Backend)
  rescue
    _ -> false
  end

  @doc """
  Configures EMLX for the current platform.

  - On iOS: sets `{EMLX.Backend, device: :gpu}` as the Nx default backend.
    JIT is disabled on real devices (W^X policy) and enabled on simulator.
  - On other platforms: falls back to `Nx.BinaryBackend`.
  """
  @spec setup() :: :ok
  def setup do
    if available?() do
      platform = detect_platform()

      jit_enabled =
        case platform do
          :ios_device -> false
          :ios_simulator -> true
          _ -> false
        end

      Application.put_env(:emlx, :jit_enabled, jit_enabled)
      Nx.default_backend({EMLX.Backend, device: :gpu})
      :ok
    else
      Application.put_env(:emlx, :jit_enabled, false)
      Nx.default_backend(Nx.BinaryBackend)
      :ok
    end
  end

  @doc """
  Returns `true` if running on a real iOS device (not simulator).
  """
  @spec ios_device?() :: boolean()
  def ios_device? do
    detect_platform() == :ios_device
  end

  @doc """
  Returns `true` if running in iOS Simulator.
  """
  @spec ios_simulator?() :: boolean()
  def ios_simulator? do
    detect_platform() == :ios_simulator
  end

  @doc """
  Returns the platform-specific configuration map.
  """
  @spec platform_config() :: %{jit_enabled: boolean(), device: atom()}
  def platform_config do
    platform = detect_platform()

    %{
      jit_enabled: platform == :ios_simulator,
      device: platform
    }
  end

  @doc """
  Returns the default device for the current platform.
  """
  @spec default_device() :: atom()
  def default_device do
    if available?() do
      :gpu
    else
      :cpu
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp detect_platform do
    try do
      case Dala.Platform.Native.platform() do
        :ios ->
          if ios_simulator_env?(), do: :ios_simulator, else: :ios_device

        :android ->
          :android

        _ ->
          :other
      end
    rescue
      _ -> :other
    end
  end

  defp ios_simulator_env? do
    case System.get_env("SIMULATOR_UDID") do
      nil ->
        # Fallback: check if we're on macOS (likely simulator during dev)
        match?({:unix, :darwin}, :os.type())

      _ ->
        true
    end
  end
end
