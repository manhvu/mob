defmodule Mob.Linking do
  @moduledoc """
  Linking API for opening URLs and handling deep links.

  ## Examples

      # Open an external URL
      socket = Mob.Linking.open_url(socket, "https://example.com")

      # Check if a URL can be opened
      Mob.Linking.can_open?("https://example.com") #=> false (stub)

      # Get the initial URL that launched the app
      Mob.Linking.initial_url() #=> nil (stub)

  Incoming deep link messages are delivered to screens via `handle_info/2`:

      def handle_info({:linking, :url, url}, socket) do
        # Process deep link URL
        {:noreply, socket}
      end
  """

  @spec open_url(Mob.Socket.t(), String.t()) :: Mob.Socket.t()
  def open_url(socket, url) when is_binary(url) do
    socket
  end

  @spec can_open?(String.t()) :: boolean()
  def can_open?(url) when is_binary(url) do
    false
  end

  @spec initial_url() :: String.t() | nil
  def initial_url() do
    nil
  end
end
