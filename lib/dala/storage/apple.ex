defmodule Dala.Storage.Apple do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  iOS-specific storage locations and media library integration.

  ## Locations

  All locations from `Dala.Storage` plus:

    - `:icloud` — iCloud Drive container for this app; `nil` if iCloud is
                  unavailable or the user has not signed in

  ## File sharing

  `Documents/` is user-visible in the Files app only when
  `UIFileSharingEnabled` is set in your `Info.plist`. Run:

      mix dala.enable file_sharing

  to add that key. Without it, `dir(:documents)` still works but the
  directory is invisible outside the app.

  ## Photo library

  `save_to_photo_library/2` saves any image or video file to the user's
  Camera Roll. It is asynchronous — the result arrives via `handle_info`:

      handle_info({:storage, :saved_to_library, path}, socket)
      handle_info({:storage, :error, :save_to_library, reason}, socket)

  Requires `NSPhotoLibraryAddUsageDescription` in `Info.plist`:

      mix dala.enable photo_library
  """

  @locations [:temp, :documents, :cache, :app_support, :icloud]

  @doc """
  Resolve a location atom to its absolute path.

  Returns `nil` for `:icloud` when iCloud is unavailable.
  """
  @spec dir(atom()) :: String.t() | nil
  def dir(location) when location in @locations do
    case Dala.Native.storage_dir(location) do
      nil -> nil
      path -> IO.iodata_to_binary(path)
    end
  end

  @doc """
  Save a file to the user's Camera Roll (photo library).

  Type (`:image` or `:video`) is inferred from the file extension.
  """
  @spec save_to_photo_library(Dala.Socket.t(), String.t()) :: Dala.Socket.t()
  def save_to_photo_library(socket, path) do
    Dala.Native.storage_save_to_photo_library(path)
    socket
  end
end
