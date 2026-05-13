defmodule Dala.Spark.Pubsub do
  @moduledoc """
  Spark DSL extension for declarative PubSub subscriptions in Dala screens.

  Allows screens to declare topic subscriptions directly in the DSL,
  with automatic subscribe/unsubscribe lifecycle management.

  ## Usage

      defmodule MyApp.ChatScreen do
        use Dala.Spark.Dsl

        dala do
          attribute :messages, :list, default: []

          pubsub do
            subscribe "chat:room:123", on_message: :handle_chat
          end

          screen name: :chat do
            column do
              text "Messages: @messages"
            end
          end
        end

        def handle_chat({:message, text}, socket) do
          messages = socket.assigns.messages ++ [text]
          {:noreply, Dala.Socket.assign(socket, :messages, messages)}
        end
      end
  """

  # Define entities first
  defmodule Subscription do
    @moduledoc false
    defstruct topic: nil, on_message: nil, __spark_metadata__: nil
  end

  @subscription %Spark.Dsl.Entity{
    name: :subscribe,
    target: Subscription,
    describe: "Subscribe to a PubSub topic with a message handler",
    args: [:topic],
    schema: [
      topic: [type: :string, required: true, doc: "Topic to subscribe to"],
      on_message: [
        type: :atom,
        required: true,
        doc: "Handler function name to call when message arrives"
      ]
    ]
  }

  @pubsub_section %Spark.Dsl.Section{
    name: :pubsub,
    describe: "Declare PubSub subscriptions for this screen",
    entities: [@subscription]
  }

  # Now register the extension with the section
  use Spark.Dsl.Extension,
    sections: [@pubsub_section]

  def get_subscriptions(dsl_state) do
    Spark.Dsl.Transformer.get_entities(dsl_state, [@subscription])
  end
end
