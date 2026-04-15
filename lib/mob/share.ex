defmodule Mob.Share do
  @moduledoc """
  System share sheet. Opens the OS share dialog with a piece of content.
  Fire-and-forget — no response arrives in the BEAM.

  ## Usage

      def handle_event("share", _params, socket) do
        Mob.Share.text(socket, "Check out Mob: https://github.com/genericjam/mob")
        {:noreply, socket}
      end

  iOS: `UIActivityViewController`
  Android: `Intent.ACTION_SEND` via `Intent.createChooser`
  """

  @doc """
  Open the share sheet with plain text. Returns the socket unchanged.
  """
  @spec text(Mob.Socket.t(), binary()) :: Mob.Socket.t()
  def text(socket, content) when is_binary(content) do
    :mob_nif.share_text(content)
    socket
  end
end
