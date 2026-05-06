defmodule Dala.Linking do
  @compile {:nowarn_undefined, [:dala_nif]}
  @moduledoc """
  Linking API for opening URLs and handling deep links.

  ## Examples

      # Open an external URL
      socket = Dala.Linking.open_url(socket, "https://example.com")

      # Check if a URL can be opened
      Dala.Linking.can_open?("https://example.com") #=> true | false

      # Get the initial URL that launched the app
      Dala.Linking.initial_url() #=> nil | "https://..."

  Incoming deep link messages are delivered to screens via `handle_info/2`:

      def handle_info({:linking, :url, url}, socket) do
        # Process deep link URL
        {:noreply, socket}
      end
  """

  @spec open_url(Dala.Socket.t(), String.t()) :: Dala.Socket.t()
  def open_url(socket, url) when is_binary(url) do
    :dala_nif.linking_open_url(url)
    socket
  end

  @spec can_open?(String.t()) :: boolean()
  def can_open?(url) when is_binary(url) do
    :dala_nif.linking_can_open(url)
  end

  @spec initial_url() :: String.t() | nil
  def initial_url() do
    :dala_nif.linking_initial_url()
  end
end
