defmodule Dala.Event.Trace do
  @moduledoc """
  Live tracing of Dala events for IEx debugging.

  Subscribe a process to receive every event that flows through `Dala.Event`.
  Uses ETS for the registry; tracing is opt-in and adds zero cost when no
  tracers are registered.

  ## Usage

      # In IEx connected to the running app:
      Dala.Event.Trace.start()
      Dala.Event.Trace.subscribe()

      # Now every event delivered via Dala.Event.dispatch/4 also lands in your
      # mailbox tagged {:dala_trace, addr, event, payload}. Pattern-match it,
      # log it, whatever.

      flush()  # see what's in the mailbox

      # Filter on the way out:
      Dala.Event.Trace.subscribe(fn addr -> addr.widget == :list end)

      # Stop tracing:
      Dala.Event.Trace.unsubscribe()
      Dala.Event.Trace.stop()

  ## Performance

  When no tracers are registered (the default), `Dala.Event.dispatch/4` does
  one ETS lookup: `:ets.whereis(:dala_event_trace)` returns `:undefined` and
  the trace branch is a no-op. Cost ~50ns per dispatch.

  When tracers are registered, each one is `send`ed a copy of the envelope.
  Tracer filter functions run in the dispatch path, so keep them cheap.
  """

  alias Dala.Event.Address

  @table :dala_event_trace

  @doc """
  Start the tracing table. Idempotent — safe to call multiple times.
  Call once at app startup if you want tracing always available.
  """
  @spec start() :: :ok
  def start do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Stop tracing and tear down the table.
  """
  @spec stop() :: :ok
  def stop do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table)
    end

    :ok
  end

  @doc """
  Subscribe the current process to receive trace messages.

  If `filter` is provided, only events for which `filter.(addr)` returns
  truthy are delivered to this subscriber.

  Messages arrive shaped `{:dala_trace, addr, event, payload}`.
  """
  @spec subscribe((Address.t() -> boolean()) | nil) :: :ok
  def subscribe(filter \\ nil) do
    start()
    :ets.insert(@table, {self(), filter})
    :ok
  end

  @doc "Unsubscribe the current process."
  @spec unsubscribe() :: :ok
  def unsubscribe do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table, self())
    end

    :ok
  end

  @doc """
  Called by `Dala.Event.dispatch/4` to deliver to all tracers. Internal API.

  Only iterates if the table exists (cheap miss when tracing is disabled).
  """
  @spec broadcast(Address.t(), atom(), term()) :: :ok
  def broadcast(%Address{} = addr, event, payload) when is_atom(event) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _ ->
        :ets.foldl(
          fn {pid, filter}, _ ->
            if Process.alive?(pid) and matches?(filter, addr) do
              send(pid, {:dala_trace, addr, event, payload})
            else
              if not Process.alive?(pid), do: :ets.delete(@table, pid)
            end

            :ok
          end,
          :ok,
          @table
        )

        :ok
    end
  end

  defp matches?(nil, _addr), do: true

  defp matches?(filter, addr) when is_function(filter, 1) do
    try do
      !!filter.(addr)
    rescue
      _ -> false
    end
  end
end
