defmodule Mob.Native do
  @moduledoc """
  Native implementation using Rustler NIFs.

  This module replaces the old mob_nif.erl with Rust-based NIFs that work
  on both iOS and Android platforms.
  """

  use Rustler,
    otp_app: :mob,
    crate: :mob_nif

  # NIF function declarations
  # These are the Rustler NIF functions defined in native/mob_nif/src/lib.rs

  @doc "Returns the platform (:ios or :android)"
  def platform, do: :erlang.nif_error(:nif_not_loaded)

  @doc "Log a message"
  def log(msg), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Log a message with a level"
  def log_level(level, msg), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Set transition type for next root change"
  def set_transition(transition), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Set the root UI tree from JSON"
  def set_root(json), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Batch register tap handlers (replaces clear_taps + individual register_tap)"
  def set_taps(taps), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Register a tap handler, returns handle"
  def register_tap(pid), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Clear all tap handlers"
  def clear_taps, do: :erlang.nif_error(:nif_not_loaded)

  @doc "Exit the app"
  def exit_app, do: :erlang.nif_error(:nif_not_loaded)

  @doc "Get safe area insets"
  def safe_area, do: :erlang.nif_error(:nif_not_loaded)

  # Device APIs (to be implemented in Rust)
  def haptic(_type), do: :erlang.nif_error(:nif_not_loaded)
  def clipboard_put(_text), do: :erlang.nif_error(:nif_not_loaded)
  def clipboard_get, do: :erlang.nif_error(:nif_not_loaded)
  def share_text(_text), do: :erlang.nif_error(:nif_not_loaded)

  # Permissions
  def request_permission(_cap), do: :erlang.nif_error(:nif_not_loaded)

  # Biometric
  def biometric_authenticate(_reason), do: :erlang.nif_error(:nif_not_loaded)

  # Location
  def location_get_once, do: :erlang.nif_error(:nif_not_loaded)
  def location_start(_accuracy), do: :erlang.nif_error(:nif_not_loaded)
  def location_stop, do: :erlang.nif_error(:nif_not_loaded)

  # Camera
  def camera_capture_photo(_quality), do: :erlang.nif_error(:nif_not_loaded)
  def camera_capture_video(_max_duration), do: :erlang.nif_error(:nif_not_loaded)
  def camera_start_preview(_opts_json), do: :erlang.nif_error(:nif_not_loaded)
  def camera_stop_preview, do: :erlang.nif_error(:nif_not_loaded)

  # Photo library
  def photos_pick(_max, _types), do: :erlang.nif_error(:nif_not_loaded)

  # File picker
  def files_pick(_mime_types), do: :erlang.nif_error(:nif_not_loaded)

  # Audio
  def audio_start_recording(_opts_json), do: :erlang.nif_error(:nif_not_loaded)
  def audio_stop_recording, do: :erlang.nif_error(:nif_not_loaded)
  def audio_play(_path, _opts_json), do: :erlang.nif_error(:nif_not_loaded)
  def audio_stop_playback, do: :erlang.nif_error(:nif_not_loaded)
  def audio_set_volume(_volume), do: :erlang.nif_error(:nif_not_loaded)

  # Motion sensors
  def motion_start(_sensors, _interval), do: :erlang.nif_error(:nif_not_loaded)
  def motion_stop, do: :erlang.nif_error(:nif_not_loaded)

  # QR/barcode scanner
  def scanner_scan(_formats_json), do: :erlang.nif_error(:nif_not_loaded)

  # Notifications
  def notify_schedule(_opts_json), do: :erlang.nif_error(:nif_not_loaded)
  def notify_cancel(_id), do: :erlang.nif_error(:nif_not_loaded)
  def notify_register_push, do: :erlang.nif_error(:nif_not_loaded)
  def take_launch_notification, do: :erlang.nif_error(:nif_not_loaded)

  # Storage
  def storage_dir(_location), do: :erlang.nif_error(:nif_not_loaded)
  def storage_save_to_photo_library(_path), do: :erlang.nif_error(:nif_not_loaded)
  def storage_save_to_media_store(_path, _type), do: :erlang.nif_error(:nif_not_loaded)
  def storage_external_files_dir(_type), do: :erlang.nif_error(:nif_not_loaded)

  # Alerts/overlays
  def alert_show(_title, _message, _buttons_json), do: :erlang.nif_error(:nif_not_loaded)
  def action_sheet_show(_title, _buttons_json), do: :erlang.nif_error(:nif_not_loaded)
  def toast_show(_message, _duration), do: :erlang.nif_error(:nif_not_loaded)

  # WebView
  def webview_eval_js(_code), do: :erlang.nif_error(:nif_not_loaded)
  def webview_post_message(_json), do: :erlang.nif_error(:nif_not_loaded)
  def webview_can_go_back, do: :erlang.nif_error(:nif_not_loaded)
  def webview_go_back, do: :erlang.nif_error(:nif_not_loaded)

  # Linking
  @doc "Open URL externally"
  def linking_open_url(_url), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Check if URL can be opened"
  def linking_can_open(_url), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Get initial URL that launched the app"
  def linking_initial_url, do: :erlang.nif_error(:nif_not_loaded)

  # Settings
  @doc "Get a setting value"
  def settings_get(_key), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Set a setting value"
  def settings_set(_key, _value), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Watch a setting key for changes"
  def settings_watch(_key), do: :erlang.nif_error(:nif_not_loaded)

  # Blob
  @doc "Create a blob from binary data"
  def blob_create(_data, _type), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Slice a blob"
  def blob_slice(_ref, _start, _end), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Convert blob to base64"
  def blob_to_base64(_ref), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Save blob to file"
  def blob_to_file(_ref, _path), do: :erlang.nif_error(:nif_not_loaded)

  # Native view components
  def register_component(_pid), do: :erlang.nif_error(:nif_not_loaded)
  def deregister_component(_handle), do: :erlang.nif_error(:nif_not_loaded)

  # Test harness
  def ui_tree, do: :erlang.nif_error(:nif_not_loaded)
  def ui_debug, do: :erlang.nif_error(:nif_not_loaded)
  def tap(_label), do: :erlang.nif_error(:nif_not_loaded)
  def tap_xy(_x, _y), do: :erlang.nif_error(:nif_not_loaded)
  def type_text(_text), do: :erlang.nif_error(:nif_not_loaded)
  def delete_backward, do: :erlang.nif_error(:nif_not_loaded)
  def key_press(_key), do: :erlang.nif_error(:nif_not_loaded)
  def clear_text, do: :erlang.nif_error(:nif_not_loaded)
  def long_press_xy(_x, _y, _ms), do: :erlang.nif_error(:nif_not_loaded)
  def swipe_xy(_x1, _y1, _x2, _y2), do: :erlang.nif_error(:nif_not_loaded)
end
