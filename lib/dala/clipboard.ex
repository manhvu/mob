defmodule Dala.Clipboard do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  System clipboard access. No permission required.

  ## Write

      def handle_event("copy", _params, socket) do
        Dala.Clipboard.put(socket, socket.assigns.text)
        {:noreply, socket}
      end

  ## Read

      def handle_event("paste", _params, socket) do
        case Dala.Clipboard.get(socket) do
          {:clipboard, :ok, text} -> {:noreply, Dala.Socket.assign(socket, :field, text)}
          {:clipboard, :empty}    -> {:noreply, socket}
        end
      end

  `get/1` dispatches to the main thread synchronously (same model as
  `safe_area/0`) — fast enough to call from any callback.
  """

  @doc """
  Write `text` to the system clipboard. Fire-and-forget; returns the socket.
  """
  @spec put(Dala.Socket.t(), binary()) :: Dala.Socket.t()
  def put(socket, text) when is_binary(text) do
    Dala.Native.clipboard_put(text)
    socket
  end

  @doc """
  Read the current clipboard text synchronously.

  Returns `{:clipboard, :ok, text}` or `{:clipboard, :empty}`.
  """
  @spec get(Dala.Socket.t()) :: {:clipboard, :ok, binary()} | {:clipboard, :empty}
  def get(_socket) do
    case Dala.Native.clipboard_get() do
      {:ok, text} -> {:clipboard, :ok, text}
      :empty -> {:clipboard, :empty}
    end
  end
end
