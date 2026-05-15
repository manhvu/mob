defmodule Dala.Screen.Manager do
  @moduledoc """
  Central registry for tracking all active screens in the application.

  Screens auto-register when started and can be queried by id, name, or pid.
  Monitors registered screens so crashed processes are cleaned up automatically.
  """

  use GenServer

  @table :dala_screen_registry
  @id_counter :dala_screen_id_counter

  @doc "Starts the screen manager (supervision child spec)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, {:keypos, 1}])
    end

    if :ets.whereis(@id_counter) == :undefined do
      :ets.new(@id_counter, [:set, :public, :named_table, {:keypos, 1}])
    end

    :ets.insert(@id_counter, {:counter, 0})
    {:ok, %{monitors: %{}}}
  end

  @impl true
  def terminate(_reason, _state) do
    # Clean up ETS tables when the manager stops
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    if :ets.whereis(@id_counter) != :undefined, do: :ets.delete(@id_counter)
    :ok
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{monitors: monitors} = state) do
    # A monitored screen process crashed — clean up its ETS entries
    :ets.match_delete(@table, {:_, :_, pid, :_})
    monitors = Map.delete(monitors, pid)
    {:noreply, %{state | monitors: monitors}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @doc """
  Generates a unique screen ID.
  """
  @spec next_id() :: integer()
  def next_id do
    :ets.update_counter(@id_counter, :counter, {2, 1}, {2, 0})
  end

  @doc """
  Registers a screen with the registry.

  - `id`: auto-generated unique integer ID
  - `name`: optional screen name (atom or nil)
  - `pid`: screen process PID
  - `module`: screen module (e.g., `MyApp.HomeScreen`)
  """
  @spec register(integer(), atom() | nil, pid(), module()) :: :ok
  def register(id, name, pid, module) when is_integer(id) and is_pid(pid) do
    :ets.insert(@table, {id, name, pid, module})
    # Monitor the screen process so we clean up if it crashes
    GenServer.cast(__MODULE__, {:monitor, pid})
    :ok
  end

  @impl true
  def handle_cast({:monitor, pid}, %{monitors: monitors} = state) do
    unless Map.has_key?(monitors, pid) do
      ref = Process.monitor(pid)
      {:noreply, %{state | monitors: Map.put(monitors, pid, ref)}}
    else
      {:noreply, state}
    end
  end

  @doc "Unregisters a screen by its PID (called when screen stops)."
  @spec unregister(pid()) :: :ok
  def unregister(pid) when is_pid(pid) do
    :ets.match_delete(@table, {:_, :_, pid, :_})

    :ok
  end

  @doc """
  Sends a message to a screen identified by `identifier` (id, name, or pid).

  Returns `:ok` if sent, `{:error, :not_found}` if identifier doesn't match any screen.
  """
  @spec dispatch(pid() | atom() | integer(), term()) :: :ok | {:error, :not_found}
  def dispatch(identifier, message) do
    case lookup_pid(identifier) do
      {:ok, pid} ->
        send(pid, message)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all registered screens as a list of maps with `:id`, `:name`, `:pid`, `:module`.
  """
  @spec list() :: [%{id: integer(), name: atom() | nil, pid: pid(), module: module()}]
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {id, name, pid, module} ->
      %{id: id, name: name, pid: pid, module: module}
    end)
  end

  defp lookup_pid(pid) when is_pid(pid) do
    case :ets.match_object(@table, {:_, :_, pid, :_}) do
      [_ | _] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp lookup_pid(id) when is_integer(id) do
    case :ets.lookup(@table, id) do
      [{^id, _, pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp lookup_pid(name) when is_atom(name) do
    case :ets.match_object(@table, {:_, name, :_, :_}) do
      [{_, ^name, pid, _} | _] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
