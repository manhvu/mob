defmodule MLApp do
  @moduledoc """
  ML App demonstrating on-device object detection with YOLO and EMLX.

  ## Features:
  - Real-time object detection using YOLO (via EMLX)
  - Camera integration for live detection
  - No configuration needed - everything auto-setups!

  ## How to run:

      cd examples/ml_app
      mix deps.get
      # For iOS (requires EMLX dependencies):
      mix mob.deploy --native --ios-sim
      # For Android:
      mix mob.deploy --native --android-emu

  ## Dependencies (automatically added by mix.exs):

  - {:mob, path: ".."} - Mob framework
  - {:nx, github: "elixir-nx/nx", sparse: "nx"} - Tensor library
  - {:emlx, github: "elixir-nx/emlx", branch: "main"} - MLX backend for Apple Silicon
  - {:axon, "~> 0.6"} - Neural network library

  Note: EMLX only works on iOS/Android with Metal/Vulkan GPU support.
  On other platforms, the app falls back to CPU-based Nx.
  """
  use Mob.App

  def navigation(_platform) do
    stack(:home, root: MLApp.HomeScreen, title: "Object Detection")
  end

  def on_start do
    # Auto-configure ML backend (zero config!)
    case Mob.ML.EMLX.setup() do
      {:ok, config} ->
        :mob_nif.log("MLApp: EMLX configured - device: #{config.device}")

      :ok ->
        :mob_nif.log("MLApp: Using default Nx backend (non-iOS)")
    end

    {:ok, _pid} = Mob.Screen.start_root(MLApp.HomeScreen)
    :ok
  end
end
