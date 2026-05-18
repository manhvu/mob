defmodule Dala.Media.Clock do
  @moduledoc """
  Realtime frame-clock for AV sync and animation.

  Uses audio clock as master (audio glitches are more noticeable than video drops).
  Drives the animation system and frame pacing.

  Architecture:
      Audio Clock (master)
          ↓
      Frame Pacer
          ↓
      Video Frame Selection
          ↓
      Frame Presentation
  """

  use GenServer

  require Logger

  @type clock_ref :: pid()
  @type timestamp_us :: integer()

  @default_fps 60

  defstruct [
    :target_fps,
    :frame_budget_us,
    :audio_clock_us,
    :video_clock_us,
    :frame_count,
    :dropped_frames,
    :last_frame_us,
    :drift_us,
    :listeners,
    :timer_ref,
  ]

  # Client API

  @doc "Start the frame clock."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Start ticking at the target FPS."
  @spec start_ticking(clock_ref()) :: :ok
  def start_ticking(pid), do: GenServer.cast(pid, :start_ticking)

  @doc "Stop ticking."
  @spec stop_ticking(clock_ref()) :: :ok
  def stop_ticking(pid), do: GenServer.cast(pid, :stop_ticking)

  @doc "Register a listener process that receives `{:clock, :tick, %{frame: n, timestamp_us: us}}`."
  @spec subscribe(clock_ref(), pid()) :: :ok
  def subscribe(pid, listener), do: GenServer.cast(pid, {:subscribe, listener})

  @doc "Unsubscribe a listener."
  @spec unsubscribe(clock_ref(), pid()) :: :ok
  def unsubscribe(pid, listener), do: GenServer.cast(pid, {:unsubscribe, listener})

  @doc "Update the audio master clock (called by audio output callback)."
  @spec update_audio_clock(clock_ref(), timestamp_us()) :: :ok
  def update_audio_clock(pid, timestamp_us) do
    GenServer.cast(pid, {:audio_clock, timestamp_us})
  end

  @doc "Report a video frame presentation (called by video renderer)."
  @spec report_video_frame(clock_ref(), timestamp_us()) :: :ok
  def report_video_frame(pid, pts_us) do
    GenServer.cast(pid, {:video_frame, pts_us})
  end

  @doc "Get current AV drift in microseconds."
  @spec drift(clock_ref()) :: integer()
  def drift(pid), do: GenServer.call(pid, :get_drift)

  @doc "Get frame statistics."
  @spec stats(clock_ref()) :: %{
    frame_count: non_neg_integer(),
    dropped_frames: non_neg_integer(),
    drift_us: integer(),
    target_fps: pos_integer()
  }
  def stats(pid), do: GenServer.call(pid, :get_stats)

  # Server callbacks

  @impl GenServer
  def init(opts) do
    target_fps = Keyword.get(opts, :target_fps, @default_fps)

    {:ok, %__MODULE__{
      target_fps: target_fps,
      frame_budget_us: div(1_000_000, target_fps),
      audio_clock_us: 0,
      video_clock_us: 0,
      frame_count: 0,
      dropped_frames: 0,
      last_frame_us: nil,
      drift_us: 0,
      listeners: [],
      timer_ref: nil,
    }}
  end

  @impl GenServer
  def handle_cast(:start_ticking, state) do
    timer_ref = schedule_tick(state.frame_budget_us)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  def handle_cast(:stop_ticking, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    {:noreply, %{state | timer_ref: nil}}
  end

  def handle_cast({:subscribe, pid}, state) do
    {:noreply, %{state | listeners: [pid | state.listeners]}}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, %{state | listeners: List.delete(state.listeners, pid)}}
  end

  def handle_cast({:audio_clock, timestamp_us}, %__MODULE__{} = state) do
    drift = timestamp_us - state.video_clock_us

    dropped =
      if abs(drift) > state.frame_budget_us * 2 do
        div(abs(drift), state.frame_budget_us)
      else
        0
      end

    {:noreply, %__MODULE__{state |
      audio_clock_us: timestamp_us,
      drift_us: drift,
      dropped_frames: state.dropped_frames + dropped
    }}
  end

  def handle_cast({:video_frame, pts_us}, state) do
    {:noreply, %{state | video_clock_us: pts_us}}
  end

  @impl GenServer
  def handle_info(:tick, %__MODULE__{} = state) do
    now = System.monotonic_time(:microsecond)
    frame_count = state.frame_count + 1

    for listener <- state.listeners do
      send(listener, {:clock, :tick, %{
        frame: frame_count,
        timestamp_us: now,
        drift_us: state.drift_us
      }})
    end

    timer_ref = schedule_tick(state.frame_budget_us)

    {:noreply, %__MODULE__{state |
      frame_count: frame_count,
      last_frame_us: now,
      timer_ref: timer_ref
    }}
  end

  @impl GenServer
  def handle_call(:get_drift, _from, state), do: {:reply, state.drift_us, state}

  def handle_call(:get_stats, _from, state) do
    {:reply, %{
      frame_count: state.frame_count,
      dropped_frames: state.dropped_frames,
      drift_us: state.drift_us,
      target_fps: state.target_fps
    }, state}
  end

  # Private

  defp schedule_tick(interval_us) do
    Process.send_after(self(), :tick, div(interval_us, 1000))
  end
end
