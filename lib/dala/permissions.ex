defmodule Dala.Permissions do
  @compile {:nowarn_undefined, [:dala_nif, :Nx]}
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
    - `:bluetooth`
    - `:wifi`

  Capabilities that need *no* permission: haptics, clipboard, share sheet, file picker.
  """

  @type capability ::
          :camera | :microphone | :photo_library | :location | :notifications | :bluetooth | :wifi

  @doc """
  Request an OS permission from the user.

  The system dialog is shown asynchronously. The result arrives in
  `handle_info/2`:

      def handle_info({:permission, :camera, :granted}, socket), do: ...
      def handle_info({:permission, :camera, :denied},  socket), do: ...

  Safe to call if the permission is already granted — the result still arrives
  via `handle_info` with the current status.

  Capabilities that do not require permission (haptics, clipboard, share sheet,
  file picker) will raise `FunctionClauseError` — do not call `request/2` for them.
  """
  @spec request(Dala.Socket.t(), capability()) :: Dala.Socket.t()
  def request(socket, capability)
      when capability in [
             :camera,
             :microphone,
             :photo_library,
             :location,
             :notifications,
             :bluetooth,
             :wifi
           ] do
    :dala_nif.request_permission(capability)
    socket
  end
end
