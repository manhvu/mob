defmodule Dala.Media.Pipeline do
  @moduledoc """
  High-level media pipeline orchestrator.

  Ties together all media subsystems into a coherent pipeline:

      Stream → Decode → Texture Pool → Scene Compositor → GPU Surface
                  ↑           ↑              ↑
              Adaptive    Subtitles     Filters/Effects
              Bitrate        ↑              ↑
                  ↑       Clock ←──── Animation
                  └────────┘

  ## Example

      {:ok, pipeline} = Dala.Media.Pipeline.start(%{
        url: "https://example.com/stream.m3u8",
        width: 1920,
        height: 1080,
        fps: 60,
        subtitles: "subtitles.srt",
        filters: [:blur, :lut],
        adaptive: true
      })

      Dala.Media.Pipeline.play(pipeline)
      Dala.Media.Pipeline.pause(pipeline)
      Dala.Media.Pipeline.stop(pipeline)
  """

  use GenServer

  require Logger

  @type pipeline_ref :: pid()
  @type config :: %{
    url: String.t(),
    width: non_neg_integer(),
    height: non_neg_integer(),
    fps: pos_integer(),
    subtitles: String.t() | nil,
    filters: [atom()],
    adaptive: boolean(),
    loop: boolean(),
    volume: float(),
  }

  defstruct [
    :config,
    :video_pid,
    :clock_pid,
    :scene_pid,
    :anim_pid,
    :texture_pool_pid,
    :adaptive_pid,
    :subtitle_cues,
    :filter_list,
    :state,  # :idle | :playing | :paused | :error
  ]

  # Client API

  @doc "Start a media pipeline with the given configuration."
  @spec start(map()) :: {:ok, pipeline_ref()} | {:error, term()}
  def start(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc "Start playback."
  @spec play(pipeline_ref()) :: :ok
  def play(pid), do: GenServer.cast(pid, :play)

  @doc "Pause playback."
  @spec pause(pipeline_ref()) :: :ok
  def pause(pid), do: GenServer.cast(pid, :pause)

  @doc "Stop playback and release all resources."
  @spec stop(pipeline_ref()) :: :ok
  def stop(pid), do: GenServer.stop(pid)

  @doc "Seek to a position in milliseconds."
  @spec seek(pipeline_ref(), non_neg_integer()) :: :ok
  def seek(pid, position_ms), do: GenServer.cast(pid, {:seek, position_ms})

  @doc "Get pipeline state."
  @spec get_state(pipeline_ref()) :: atom()
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc "Get pipeline diagnostics."
  @spec diagnostic(pipeline_ref()) :: map()
  def diagnostic(pid), do: GenServer.call(pid, :diagnostic)

  @doc "Add a filter to the running pipeline."
  @spec add_filter(pipeline_ref(), atom(), map()) :: :ok | {:error, term()}
  def add_filter(pid, filter_type, params \\ %{}) do
    GenServer.call(pid, {:add_filter, filter_type, params})
  end

  @doc "Remove a filter from the running pipeline."
  @spec remove_filter(pipeline_ref(), atom()) :: :ok
  def remove_filter(pid, filter_type) do
    GenServer.cast(pid, {:remove_filter, filter_type})
  end

  # Server callbacks

  @impl GenServer
  def init(config) do
    state = %__MODULE__{
      config: config,
      video_pid: nil,
      clock_pid: nil,
      scene_pid: nil,
      anim_pid: nil,
      texture_pool_pid: nil,
      adaptive_pid: nil,
      subtitle_cues: [],
      filter_list: Map.get(config, :filters, []),
      state: :idle,
    }

    case setup_pipeline(state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_cast(:play, %{state: :playing} = state), do: {:noreply, state}

  def handle_cast(:play, state) do
    if state.video_pid, do: Dala.Media.Video.play(state.video_pid)
    if state.clock_pid, do: Dala.Media.Clock.start_ticking(state.clock_pid)
    {:noreply, %{state | state: :playing}}
  end

  def handle_cast(:pause, state) do
    if state.video_pid, do: Dala.Media.Video.pause(state.video_pid)
    if state.clock_pid, do: Dala.Media.Clock.stop_ticking(state.clock_pid)
    {:noreply, %{state | state: :paused}}
  end

  def handle_cast({:seek, position_ms}, state) do
    if state.video_pid, do: Dala.Media.Video.seek(state.video_pid, position_ms)
    {:noreply, state}
  end

  def handle_cast({:remove_filter, filter_type}, state) do
    filter_list = List.delete(state.filter_list, filter_type)
    {:noreply, %{state | filter_list: filter_list}}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call(:diagnostic, _from, state) do
    clock_stats = if state.clock_pid, do: Dala.Media.Clock.stats(state.clock_pid), else: %{}
    adaptive_diag = if state.adaptive_pid, do: Dala.Media.Adaptive.diagnostic(state.adaptive_pid), else: %{}

    {:reply, %{
      state: state.state,
      config: Map.take(state.config, [:url, :width, :height, :fps]),
      clock: clock_stats,
      adaptive: adaptive_diag,
      filters: state.filter_list,
      subtitles: length(state.subtitle_cues),
    }, state}
  end

  def handle_call({:add_filter, filter_type, _params}, _from, state) do
    filter_list = [filter_type | state.filter_list]
    {:reply, :ok, %{state | filter_list: filter_list}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    # Tear down in reverse order
    if state.video_pid, do: Dala.Media.Video.stop(state.video_pid)
    if state.scene_pid, do: Dala.Media.Scene.destroy(state.scene_pid)
    if state.texture_pool_pid, do: Dala.Media.Texture.destroy_pool(state.texture_pool_pid)
    :ok
  end

  # Private — pipeline setup

  defp setup_pipeline(%__MODULE__{} = state) do
    config = state.config
    width = Map.get(config, :width, 1920)
    height = Map.get(config, :height, 1080)
    fps = Map.get(config, :fps, 60)

    with {:ok, video} <- Dala.Media.Video.start_stream(self(), Map.get(config, :url), [
           width: width, height: height,
           volume: Map.get(config, :volume, 1.0),
           loop: Map.get(config, :loop, false),
         ]),
         {:ok, clock} <- Dala.Media.Clock.start_link(target_fps: fps),
         {:ok, scene} <- Dala.Media.Scene.new(width, height, target_fps: fps),
         {:ok, anim} <- Dala.Media.Animation.start_link([]),
         {:ok, pool} <- Dala.Media.Texture.new_pool(width, height, count: 6),
         {:ok, adaptive} <- maybe_start_adaptive(config),
         subtitle_cues <- maybe_load_subtitles(config) do
      # Wire up clock → scene (frame-driven rendering)
      Dala.Media.Clock.subscribe(clock, scene)

      # Wire up clock → animation
      Dala.Media.Clock.subscribe(clock, anim)

      # Add video node to scene
      {:ok, _video_node} = Dala.Media.Scene.add_node(scene, :video, %{
        stream: video,
        position: {0, 0},
        size: {width, height},
        z_index: 0,
      })

      # Add subtitle overlay node if subtitles loaded
      scene =
        if subtitle_cues != [] do
          {:ok, _sub_node} = Dala.Media.Scene.add_node(scene, :text, %{
            text: "",
            position: {0, height - 80},
            size: {width, 60},
            z_index: 100,
            visible: true,
          })
          scene
        else
          scene
        end

      {:ok, %__MODULE__{state |
        video_pid: video,
        clock_pid: clock,
        scene_pid: scene,
        anim_pid: anim,
        texture_pool_pid: pool,
        adaptive_pid: adaptive,
        subtitle_cues: subtitle_cues
      }}
    end
  end

  defp maybe_start_adaptive(%{adaptive: true}) do
    {:ok, pid} = Dala.Media.Adaptive.start_link([])
    {:ok, pid}
  end

  defp maybe_start_adaptive(_), do: {:ok, nil}

  defp maybe_load_subtitles(%{subtitles: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        case Dala.Media.Subtitle.parse_srt(content) do
          {:ok, cues} -> cues
          {:error, _} -> []
        end

      {:error, _} ->
        []
    end
  end

  defp maybe_load_subtitles(_), do: []
end
