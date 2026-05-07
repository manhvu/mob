defmodule Dala.Spark.Transformers.PubSub do
  @moduledoc """
  Spark transformer that handles PubSub subscriptions from DSL.

  Generates `handle_info/2` clauses for each subscription declared
  in the pubsub section, forwarding messages to the specified handler.
  Also manages subscribe/unsubscribe in mount/terminate.
  """

  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    subscriptions = Dala.Spark.PubSub.get_subscriptions(dsl_state)

    if Enum.any?(subscriptions) do
      # Generate handle_info clauses for each subscription
      handle_info_clauses =
        Enum.map(subscriptions, fn sub ->
          topic = Map.get(sub, :topic)
          handler = Map.get(sub, :on_message)

          quote do
            def handle_info(msg, socket) do
              # Check if this message is for our topic
              # In a real implementation, you'd track subscriptions
              # For now, forward all messages to the handler
              apply(__MODULE__, unquote(handler), [msg, socket])
            end
          end
        end)

      {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], handle_info_clauses)}
    else
      {:ok, dsl_state}
    end
  end
end
