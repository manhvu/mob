defmodule Dala.Permissions do
  @moduledoc """
  Permission management for Dala plugins.

  Provides a unified interface for requesting and checking permissions
  across iOS and Android. Maps permission atoms to platform-specific
  permission strings and handles runtime request flows.

  ## Supported Permissions

  - `:camera` — Camera access
  - `:microphone` — Microphone access
  - `:bluetooth` — Bluetooth access
  - `:location` — Location services
  - `:storage` — File/storage access
  - `:photos` — Photo library access
  - `:contacts` — Contacts access
  - `:notifications` — Push notifications

  ## Usage

      # Request a permission at runtime
      Dala.Permissions.request(socket, :camera)

      # Check if a permission is granted
      Dala.Permissions.check(:camera)

      # Get all supported permissions
      Dala.Permissions.supported_permissions()
  """

  @type permission ::
          :camera
          | :microphone
          | :bluetooth
          | :location
          | :storage
          | :photos
          | :contacts
          | :notifications

  @doc "Returns all supported permissions."
  @spec supported_permissions() :: [permission()]
  def supported_permissions,
    do: [
      :camera,
      :microphone,
      :bluetooth,
      :location,
      :storage,
      :photos,
      :contacts,
      :notifications
    ]

  @doc "Checks if a permission is supported."
  @spec supported?(permission()) :: boolean()
  def supported?(permission), do: permission in supported_permissions()

  @doc "Checks if a permission is currently granted. Returns `:granted` or `:denied`."
  @spec check(permission()) :: :granted | :denied
  def check(permission) when is_atom(permission) do
    if supported?(permission) do
      case Dala.Platform.Native.check_permission(permission_string(permission)) do
        true -> :granted
        false -> :denied
      end
    else
      :denied
    end
  end

  @doc "Requests a permission. Sends `{:permission_result, permission, result}` to `pid`."
  @spec request(pid(), permission()) :: :ok | {:error, term()}
  def request(pid, permission) when is_atom(permission) do
    if supported?(permission) do
      result = Dala.Platform.Native.request_permission(permission_string(permission))
      send(pid, {:permission_result, permission, result})
      :ok
    else
      {:error, :unsupported_permission}
    end
  end

  @doc "Returns the platform-specific permission string."
  @spec permission_string(permission()) :: String.t()
  def permission_string(:camera), do: "camera"
  def permission_string(:microphone), do: "microphone"
  def permission_string(:bluetooth), do: "bluetooth"
  def permission_string(:location), do: "location"
  def permission_string(:storage), do: "storage"
  def permission_string(:photos), do: "photos"
  def permission_string(:contacts), do: "contacts"
  def permission_string(:notifications), do: "notifications"

  @doc "Returns the iOS plist key for a permission."
  @spec ios_plist_key(permission()) :: String.t() | nil
  def ios_plist_key(:camera), do: "NSCameraUsageDescription"
  def ios_plist_key(:microphone), do: "NSMicrophoneUsageDescription"
  def ios_plist_key(:bluetooth), do: "NSBluetoothAlwaysUsageDescription"
  def ios_plist_key(:location), do: "NSLocationWhenInUseUsageDescription"
  def ios_plist_key(:photos), do: "NSPhotoLibraryUsageDescription"
  def ios_plist_key(:contacts), do: "NSContactsUsageDescription"
  def ios_plist_key(_), do: nil

  @doc "Returns the Android permission string."
  @spec android_permission(permission()) :: String.t() | nil
  def android_permission(:camera), do: "CAMERA"
  def android_permission(:microphone), do: "RECORD_AUDIO"
  def android_permission(:bluetooth), do: "BLUETOOTH_CONNECT"
  def android_permission(:location), do: "ACCESS_FINE_LOCATION"
  def android_permission(:storage), do: "READ_EXTERNAL_STORAGE"
  def android_permission(:photos), do: "READ_MEDIA_IMAGES"
  def android_permission(:contacts), do: "READ_CONTACTS"
  def android_permission(:notifications), do: "POST_NOTIFICATIONS"
  def android_permission(_), do: nil

  @doc "Validates permissions, returning `:ok` or `{:error, {:unsupported, [permissions]}}`."
  @spec validate_permissions([permission()]) :: :ok | {:error, term()}
  def validate_permissions(permissions) when is_list(permissions) do
    unsupported = permissions -- supported_permissions()
    if unsupported == [], do: :ok, else: {:error, {:unsupported_permissions, unsupported}}
  end
end
