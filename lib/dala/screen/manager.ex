defmodule Dala.Screen.Manager do
  @moduledoc """
  Central registry for tracking all active screens in the application.

  Screens auto-register when started and can be queried by id, name, or pid.
  """

  use GenServer

  @table :dala_screen_registry
  @id_counter :dala_screen_id_counter

  @doc "Starts the screen manager (supervision child spec)."
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
    {:ok, %{}}
  end

  @doc """
  Generates a unique screen ID.
  """
  def next_id do
    if :ets.whereis(@id_counter) == :undefined do
      :ets.new(@id_counter, [:set, :public, :named_table, {:keypos, 1}])
      :ets.insert(@id_counter, {:counter, 1})
      0
    else
      [{:counter, id}] = :ets.lookup(@id_counter, :counter)
      :ets.insert(@id_counter, {:counter, id + 1})
      id
    end
  end

  @doc """
  Registers a screen with the registry.

  - `id`: auto-generated unique integer ID
  - `name`: optional screen name (atom or nil)
  - `pid`: screen process PID
  - `module`: screen module (e.g., `MyApp.HomeScreen`)
  """
  def register(id, name, pid, module) when is_integer(id) and is_pid(pid) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, {:keypos, 1}])
    end

    :ets.insert(@table, {id, name, pid, module})
    :ok
  end

  @doc "Unregisters a screen by its PID (called when screen stops)."
  def unregister(pid) when is_pid(pid) do
    case :ets.match_object(@table, {:_, :_, pid, :_}) do
      [entry] -> :ets.delete_object(@table, entry)
      [] -> :ok
    end

    :ok
  end

  @doc """
  Sends a message to a screen identified by `identifier` (id, name, or pid).

  Returns `:ok` if sent, `{:error, :not_found}` if identifier doesn't match any screen.
  """
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
