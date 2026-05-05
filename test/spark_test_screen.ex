defmodule Dala.SparkTestScreen do
  @moduledoc """
  Test screen using the Dala Spark DSL to verify implementation.
  """

  use Dala.Spark.Dsl

  dala do
    attribute(:count, :integer, default: 0)
    attribute(:message, :string, default: "Hello")

    screen name: :spark_test do
      text("Count: @count")
      button("Increment", on_tap: :increment)
      text("@message")
    end
  end

  def handle_event(:increment, _params, socket) do
    new_count = Dala.Socket.get_assign(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
