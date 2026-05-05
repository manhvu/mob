defmodule Dala.Photos do
  @compile {:nowarn_undefined, [:dala_nif, :Nx]}
  @moduledoc """
  Photo / video library picker.

  On iOS 14+ no permission is required (the picker itself is sandboxed).
  On Android, `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` may be needed.

  Results arrive as:

      handle_info({:photos, :picked,    items},   socket)
      handle_info({:photos, :cancelled},           socket)

  Each item in `items` is:

      %{path: "/tmp/dala_pick_xxx.jpg", type: :image | :video,
        width: 1920, height: 1080}

  iOS: `PHPickerViewController`. Android: `PickMultipleVisualMedia`.
  """

  @spec pick(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def pick(socket, opts \\ []) do
    max = Keyword.get(opts, :max, 1)
    types = Keyword.get(opts, :types, [:image]) |> Enum.map(&Atom.to_string/1)
    :dala_nif.photos_pick(max, types)
    socket
  end
end
