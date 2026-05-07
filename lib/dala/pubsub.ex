defmodule Dala.PubSub do
  @moduledoc """
  Simplified PubSub for Dala apps using Elixir's built-in Registry.

  No Redis, no adapters — just fast local pubsub for screens to communicate.

  ## Usage

      # In your app's supervision tree:
      children = [
        {Dala.PubSub, name: MyApp.PubSub}
      ]

      # Subscribe to topics:
      Dala.PubSub.subscribe(MyApp.PubSub, "user:123")

      # Broadcast messages:
      Dala.PubSub.broadcast(MyApp.PubSub, "user:123", {:update, %{id: 123}})
  """

  @type t :: atom
  @type topic :: binary
  @type message :: term

  @doc """
  Returns a child specification for pubsub with the given `options`.

  Required option:
    * `:name` - the name of the pubsub instance
  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(options) do
    name = Keyword.fetch!(options, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @doc """
  Starts a PubSub instance.

  ## Options

    * `:name` - the name of the pubsub instance (required)
  """
  @spec start_link(keyword) :: {:ok, pid} | {:error, term}
  def start_link(options) do
    name = Keyword.fetch!(options, :name)

    children = [
      {Registry, keys: :duplicate, name: name, partitions: System.schedulers_online()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: supervisor_name(name))
  end

  @doc """
  Subscribes the caller to a topic.

      Dala.PubSub.subscribe(MyApp.PubSub, "user:123")
  """
  @spec subscribe(t, topic) :: :ok | {:error, term}
  def subscribe(pubsub, topic) when is_binary(topic) do
    case Registry.register(pubsub, topic, nil) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Unsubscribes the caller from a topic.

      Dala.PubSub.unsubscribe(MyApp.PubSub, "user:123")
  """
  @spec unsubscribe(t, topic) :: :ok
  def unsubscribe(pubsub, topic) when is_binary(topic) do
    Registry.unregister(pubsub, topic)
  end

  @doc """
  Broadcasts a message to all subscribers of a topic.

      Dala.PubSub.broadcast(MyApp.PubSub, "user:123", {:update, data})
  """
  @spec broadcast(t, topic, message) :: :ok
  def broadcast(pubsub, topic, message) when is_binary(topic) do
    Registry.dispatch(pubsub, topic, fn entries ->
      for {pid, _} <- entries do
        send(pid, message)
      end
    end)

    :ok
  end

  @doc """
  Broadcasts a message to all subscribers except the sender.

      Dala.PubSub.broadcast_from(MyApp.PubSub, self(), "user:123", {:update, data})
  """
  @spec broadcast_from(t, pid, topic, message) :: :ok
  def broadcast_from(pubsub, from, topic, message) when is_binary(topic) and is_pid(from) do
    Registry.dispatch(pubsub, topic, fn entries ->
      for {pid, _} <- entries, pid != from do
        send(pid, message)
      end
    end)

    :ok
  end

  @doc """
  Returns all topics with at least one subscriber.
  """
  @spec topics(t) :: [topic]
  def topics(pubsub) do
    Registry.keys(pubsub, self()) |> Enum.uniq()
  end

  @doc """
  Returns the number of subscribers for a topic.
  """
  @spec subscriber_count(t, topic) :: non_neg_integer
  def subscriber_count(pubsub, topic) when is_binary(topic) do
    Registry.lookup(pubsub, topic) |> length()
  end

  defp supervisor_name(name) when is_atom(name) do
    Module.concat(name, Supervisor)
  end
end
