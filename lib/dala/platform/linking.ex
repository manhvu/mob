defmodule Dala.Platform.Linking do
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

  @doc """
  Open an external URL in the system browser or appropriate app.

  Returns the socket unchanged.
  """
  @spec open_url(Dala.Socket.t(), String.t()) :: Dala.Socket.t()
  def open_url(socket, url) when is_binary(url) do
    Dala.Platform.Native.linking_open_url(url)
    socket
  end

  @doc """
  Check if a URL can be opened by any installed app.

  Returns `true` if the URL scheme is handled, `false` otherwise.
  """
  @spec can_open?(String.t()) :: boolean()
  def can_open?(url) when is_binary(url) do
    Dala.Platform.Native.linking_can_open(url)
  end

  @doc """
  Get the URL that launched the app (deep link), if any.

  Returns the URL string or `nil` if the app was not launched via a URL.
  """
  @spec initial_url() :: String.t() | nil
  def initial_url() do
    Dala.Platform.Native.linking_initial_url()
  end
end
