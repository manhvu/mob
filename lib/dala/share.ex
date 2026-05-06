defmodule Dala.Share do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  System share sheet. Opens the OS share dialog with a piece of content.
  Fire-and-forget — no response arrives in the BEAM.

  ## Usage

      def handle_event("share", _params, socket) do
        Dala.Share.text(socket, "Check out Dala: https://github.com/genericjam/dala")
        {:noreply, socket}
      end

  iOS: `UIActivityViewController`
  Android: `Intent.ACTION_SEND` via `Intent.createChooser`
  """

  @doc """
  Open the share sheet with plain text. Returns the socket unchanged.
  """
  @spec text(Dala.Socket.t(), binary()) :: Dala.Socket.t()
  def text(socket, content) when is_binary(content) do
    Dala.Native.share_text(content)
    socket
  end
end
