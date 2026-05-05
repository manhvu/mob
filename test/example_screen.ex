defmodule Example.SparkScreen do
  @moduledoc """
  Example screen using Spark DSL prototype.
  """
  use Dala.Spark.Dsl

  screen :example do
    mount do
      # Initialize state
    end

    column padding: 16 do
      text(text: "Hello from Spark DSL!")
      button(text: "Tap me", on_tap: :tapped)
    end
  end

  handle_info({:tap, :tapped}, socket) do
    IO.puts("Button tapped!")
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
