defmodule Mob.Audio do
  @moduledoc """
  Microphone recording.

  Requires `:microphone` permission (request via `Mob.Permissions.request/2`).

  Usage:

      Mob.Audio.start_recording(socket, format: :aac, quality: :medium)
      # ... user records ...
      Mob.Audio.stop_recording(socket)

  Result arrives as:

      handle_info({:audio, :recorded, %{path: path, duration: seconds}}, socket)
      handle_info({:audio, :error,    reason},                            socket)

  iOS: `AVAudioRecorder`. Android: `MediaRecorder`.
  """

  @type format  :: :aac | :wav
  @type quality :: :low | :medium | :high

  @doc """
  Start recording audio from the microphone.

  Options:
    - `format: :aac | :wav` (default `:aac`)
    - `quality: :low | :medium | :high` (default `:medium`)
  """
  @spec start_recording(Mob.Socket.t(), keyword()) :: Mob.Socket.t()
  def start_recording(socket, opts \\ []) do
    format  = Keyword.get(opts, :format, :aac)  |> Atom.to_string()
    quality = Keyword.get(opts, :quality, :medium) |> Atom.to_string()
    opts_json = :json.encode(%{"format" => format, "quality" => quality})
    :mob_nif.audio_start_recording(opts_json)
    socket
  end

  @doc """
  Stop the in-progress recording and save it to a temp file.
  Result arrives as `{:audio, :recorded, %{path: ..., duration: ...}}`.
  """
  @spec stop_recording(Mob.Socket.t()) :: Mob.Socket.t()
  def stop_recording(socket) do
    :mob_nif.audio_stop_recording()
    socket
  end
end
