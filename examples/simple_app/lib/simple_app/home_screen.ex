defmodule SimpleApp.HomeScreen do
  @moduledoc """
  Home screen with counter and navigation to detail screen.
  """
  use Dala.Screen

  def mount(_params, _session, socket) do
    {:ok, Dala.Socket.assign(socket, :count, 0)}
  end

  def render(assigns) do
    %{
      type: :column,
      props: %{padding: 16, spacing: 8},
      children: [
        %{type: :text, props: %{text: "Welcome to Dala!", text_size: :xl}},
        %{type: :text, props: %{text: "Count: #{assigns.count}"}},
        %{
          type: :button,
          props: %{text: "Increment"},
          on_tap: {self(), :increment}
        },
        %{
          type: :button,
          props: %{text: "Go to Detail"},
          on_tap: {self(), :navigate}
        }
      ]
    }
  end

  def handle_event(:increment, _params, socket) do
    new_count = socket.assigns.count + 1
    {:noreply, Dala.Socket.assign(socket, :count, new_count)}
  end

  def handle_event(:navigate, _params, socket) do
    {:noreply, Dala.Screen.push_screen(socket, SimpleApp.DetailScreen)}
  end
end
