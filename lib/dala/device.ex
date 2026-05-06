defmodule Dala.Device do
  @compile {:nowarn_undefined, [:dala_nif, :Nx]}
  @moduledoc """
  Cross-platform device events and queries.

  `Dala.Device` is the single subscription point for OS-level events that exist
  on both iOS and Android. The native side (iOS `NotificationCenter`,
  Android `ProcessLifecycleObserver`) registers observers once at startup and
  emits each event as a tagged tuple to a registered dispatcher pid; this
  GenServer fans the events out to subscribers by category.

  ## Subscribe

      Dala.Device.subscribe()             # default categories
      Dala.Device.subscribe(:all)         # everything
      Dala.Device.subscribe([:app, :power])

  Subscribers receive `{:dala_device, atom}` or `{:dala_device, atom, payload}`
  in their mailbox. Default categories are `:app`, `:display`, `:audio`, `:memory`.

  ## Categories and events

  - `:app` — `:will_resign_active`, `:did_become_active`, `:did_enter_background`,
    `:will_enter_foreground`, `:will_terminate`
  - `:display` — `:screen_off`, `:screen_on`
  - `:audio` — `:audio_interrupted`, `:audio_resumed`, `:audio_route_changed`
  - `:appearance` — `{:color_scheme_changed, :light | :dark}`
  - `:power` — `{:battery_state_changed, :unplugged | :charging | :full | :unknown}`,
    `{:battery_level_changed, integer}`, `{:low_power_mode_changed, boolean}`
  - `:thermal` — `{:thermal_state_changed, :nominal | :fair | :serious | :critical}`
  - `:memory` — `:memory_warning`

  Platform-specific events with no cross-platform counterpart go through
  `Dala.Device.IOS` / `Dala.Device.Android` instead.

  ## Queries

      Dala.Device.battery_level()      # 0..100 | -1 if unknown
      Dala.Device.battery_state()      # :unplugged | :charging | :full | :unknown
      Dala.Device.thermal_state()      # :nominal | :fair | :serious | :critical
      Dala.Device.low_power_mode?()    # boolean
      Dala.Device.foreground?()        # boolean
      Dala.Device.os_version()         # binary
      Dala.Device.model()              # binary
  """

  use GenServer
  require Logger

  @categories [:app, :display, :audio, :appearance, :power, :thermal, :memory]
  @default_categories [:app, :display, :audio, :appearance, :memory]

  @app_events [
    :will_resign_active,
    :did_become_active,
    :did_enter_background,
    :will_enter_foreground,
    :will_terminate
  ]
  @display_events [:screen_off, :screen_on]
  @audio_events [:audio_interrupted, :audio_resumed, :audio_route_changed]
  @appearance_events [:color_scheme_changed]
  @power_events [:battery_state_changed, :battery_level_changed, :low_power_mode_changed]
  @thermal_events [:thermal_state_changed]
  @memory_events [:memory_warning]

  @type category :: :app | :display | :audio | :appearance | :power | :thermal | :memory
  @type event :: atom()

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Start the dispatcher. Called from `Dala.Application` (or the app supervision
  tree). After start, the registered NIF dispatcher pid is this GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe the calling process to device events.

  Accepts a single category atom, a list of categories, or `:all`.
  Default is `#{inspect(@default_categories)}`.

      Dala.Device.subscribe()
      Dala.Device.subscribe(:thermal)
      Dala.Device.subscribe([:app, :power, :thermal])
      Dala.Device.subscribe(:all)
  """
  @spec subscribe(category() | [category()] | :all) :: :ok
  def subscribe(categories \\ @default_categories) do
    GenServer.call(__MODULE__, {:subscribe, self(), normalize_categories(categories)})
  end

  @doc "Unsubscribe the calling process from all categories."
  @spec unsubscribe() :: :ok
  def unsubscribe do
    GenServer.call(__MODULE__, {:unsubscribe, self()})
  end

  @doc "Returns the configured list of valid categories."
  @spec categories() :: [category()]
  def categories, do: @categories

  # ── Queries (delegate to NIF) ─────────────────────────────────────────────

  @doc "Current battery level (0..100), or -1 if unknown."
  @spec battery_level() :: integer()
  def battery_level do
    {_state, pct} = :dala_nif.device_battery_state()
    pct
  end

  @doc "Current battery state — `:unplugged | :charging | :full | :unknown`."
  @spec battery_state() :: :unplugged | :charging | :full | :unknown
  def battery_state do
    {state, _pct} = :dala_nif.device_battery_state()
    state
  end

  @doc "Current thermal state — `:nominal | :fair | :serious | :critical`."
  @spec thermal_state() :: :nominal | :fair | :serious | :critical
  def thermal_state, do: :dala_nif.device_thermal_state()

  @doc "True if Low Power Mode (iOS) / Power Save Mode (Android) is on."
  @spec low_power_mode?() :: boolean()
  def low_power_mode?, do: :dala_nif.device_low_power_mode() == true

  @doc "True if the app is currently in the foreground."
  @spec foreground?() :: boolean()
  def foreground?, do: :dala_nif.device_foreground() == true

  @doc "OS version string (e.g. \"17.4\")."
  @spec os_version() :: String.t()
  def os_version, do: to_string(:dala_nif.device_os_version())

  @doc "Device model (e.g. \"iPhone\", \"Pixel 8\")."
  @spec model() :: String.t()
  def model, do: to_string(:dala_nif.device_model())

  # ── GenServer ─────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # Register this process as the NIF dispatcher. The native side will
    # enif_send all events here; we fan out to subscribers below.
    case maybe_set_dispatcher() do
      :ok ->
        :ok

      {:error, :nif_not_loaded} ->
        # Expected when running on the host (tests, IEx without device).
        :ok

      {:error, reason} ->
        Logger.warning("Dala.Device: NIF dispatcher not set: #{inspect(reason)}")
    end

    {:ok, %{subscribers: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:subscribe, pid, cats}, _from, state) do
    state = put_subscriber(state, pid, cats)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    state = drop_subscriber(state, pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:__test_subscribers__, _from, state) do
    {:reply, state.subscribers, state}
  end

  @impl true
  def handle_info({:dala_device, event}, state) do
    fan_out(state, event, nil)
    {:noreply, state}
  end

  def handle_info({:dala_device, event, payload}, state) do
    fan_out(state, event, payload)
    {:noreply, state}
  end

  # Platform-specific events go straight to the platform module's dispatcher.
  def handle_info({:dala_device_ios, _, _} = msg, state) do
    forward_to(Dala.Device.IOS, msg)
    {:noreply, state}
  end

  def handle_info({:dala_device_ios, _} = msg, state) do
    forward_to(Dala.Device.IOS, msg)
    {:noreply, state}
  end

  def handle_info({:dala_device_android, _, _} = msg, state) do
    forward_to(Dala.Device.Android, msg)
    {:noreply, state}
  end

  def handle_info({:dala_device_android, _} = msg, state) do
    forward_to(Dala.Device.Android, msg)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, drop_subscriber(state, pid)}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp maybe_set_dispatcher do
    try do
      :dala_nif.device_set_dispatcher(self())
      :ok
    rescue
      _ -> {:error, :nif_not_loaded}
    end
  end

  defp normalize_categories(:all), do: @categories
  defp normalize_categories(cat) when is_atom(cat), do: [cat]
  defp normalize_categories(cats) when is_list(cats), do: Enum.uniq(cats)

  defp put_subscriber(state, pid, cats) do
    monitors =
      case Map.get(state.monitors, pid) do
        nil -> Map.put(state.monitors, pid, Process.monitor(pid))
        _ref -> state.monitors
      end

    cats = MapSet.new(cats)
    subscribers = Map.put(state.subscribers, pid, cats)
    %{state | subscribers: subscribers, monitors: monitors}
  end

  defp drop_subscriber(state, pid) do
    case Map.pop(state.monitors, pid) do
      {nil, monitors} ->
        %{state | monitors: monitors}

      {ref, monitors} ->
        Process.demonitor(ref, [:flush])
        %{state | subscribers: Map.delete(state.subscribers, pid), monitors: monitors}
    end
  end

  defp fan_out(state, event, payload) do
    cat = category_for(event)

    msg =
      case payload do
        nil -> {:dala_device, event}
        p -> {:dala_device, event, p}
      end

    Enum.each(state.subscribers, fn {pid, cats} ->
      if MapSet.member?(cats, cat), do: send(pid, msg)
    end)
  end

  defp forward_to(mod, msg) do
    case Process.whereis(mod) do
      nil -> :ok
      pid -> send(pid, msg)
    end
  end

  @doc false
  @spec category_for(atom()) :: category() | :other
  def category_for(event) do
    cond do
      event in @app_events -> :app
      event in @display_events -> :display
      event in @audio_events -> :audio
      event in @appearance_events -> :appearance
      event in @power_events -> :power
      event in @thermal_events -> :thermal
      event in @memory_events -> :memory
      true -> :unknown
    end
  end
end
