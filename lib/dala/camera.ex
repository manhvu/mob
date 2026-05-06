defmodule Dala.Camera do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  Native camera capture for photos and videos.

  Requires `:camera` permission (and `:microphone` for video).

  Opens the native OS camera UI. Results arrive as:

      handle_info({:camera, :photo, %{path: path, width: w, height: h}}, socket)
      handle_info({:camera, :video, %{path: path, duration: seconds}},   socket)
      handle_info({:camera, :cancelled},                                   socket)

  The `path` is a local temp file. Copy it elsewhere before the next capture.

  iOS: `UIImagePickerController`. Android: `TakePicture` / `CaptureVideo` activity contracts.
  """

  @doc """
  Open the camera to capture a photo.

  Options:
    - `quality: :high | :medium | :low` (default `:high`) — JPEG compression level
  """
  @spec capture_photo(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def capture_photo(socket, opts \\ []) do
    quality = Keyword.get(opts, :quality, :high)
    Dala.Native.camera_capture_photo(quality)
    socket
  end

  @doc """
  Open the camera to record a video.

  Options:
    - `max_duration: integer` — maximum clip length in seconds (default `60`)
  """
  @spec capture_video(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def capture_video(socket, opts \\ []) do
    max_duration = Keyword.get(opts, :max_duration, 60)
    Dala.Native.camera_capture_video(max_duration)
    socket
  end

  @doc """
  Start a live camera preview session. Pair with a `:camera_preview` component
  in your render tree to display the feed.

  Options:
    - `facing: :back | :front` (default `:back`)
  """
  @spec start_preview(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def start_preview(socket, opts \\ []) do
    facing = Keyword.get(opts, :facing, :back) |> Atom.to_string()
    Dala.Native.camera_start_preview(:json.encode(%{"facing" => facing}))
    socket
  end

  @doc "Stop the active camera preview session."
  @spec stop_preview(Dala.Socket.t()) :: Dala.Socket.t()
  def stop_preview(socket) do
    Dala.Native.camera_stop_preview()
    socket
  end
end
