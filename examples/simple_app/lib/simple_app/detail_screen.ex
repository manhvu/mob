defmodule SimpleApp.DetailScreen do
  @moduledoc """
  Detail screen showing navigation with back button.
  """
  use Mob.Screen

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(_assigns) do
    %{
      type: :column,
      props: %{padding: 16, spacing: 8},
      children: [
        %{type: :text, props: %{text: "Detail Screen", text_size: :lg}},
        %{type: :text, props: %{text: "This is a detail view."}},
        %{
          type: :button,
          props: %{text: "Go Back"},
          on_tap: {self(), :go_back}
        }
      ]
    }
  end

  def handle_event(:go_back, _params, socket) do
    {:noreply, Mob.Screen.pop_screen(socket)}
  end
end
