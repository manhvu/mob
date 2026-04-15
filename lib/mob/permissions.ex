defmodule Mob.Permissions do
  @moduledoc """
  Request OS-level permissions from the user.

  The permission dialog is shown asynchronously. The result arrives as:

      handle_info({:permission, capability, :granted | :denied}, socket)

  Capabilities that require this:
    - `:camera`
    - `:microphone`
    - `:photo_library`
    - `:location`
    - `:notifications`

  Capabilities that need *no* permission: haptics, clipboard, share sheet, file picker.
  """

  @type capability :: :camera | :microphone | :photo_library | :location | :notifications

  @spec request(Mob.Socket.t(), capability()) :: Mob.Socket.t()
  def request(socket, capability)
      when capability in [:camera, :microphone, :photo_library, :location, :notifications] do
    :mob_nif.request_permission(capability)
    socket
  end
end
