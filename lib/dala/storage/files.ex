defmodule Dala.Storage.Files do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  System file picker. Opens the OS document picker (Files app on iOS, SAF on Android).

  No permission required — the user explicitly selects files.

  Results arrive as:

      handle_info({:files, :picked,    items},   socket)
      handle_info({:files, :cancelled},           socket)

  Each item in `items` is:

      %{path: "/tmp/dala_file_xxx.pdf", name: "report.pdf",
        mime: "application/pdf", size: 102400}

  iOS: `UIDocumentPickerViewController`. Android: `OpenMultipleDocuments`.
  """

  @doc """
  Open the system file picker.

  Options:
    * `:types` — list of MIME type patterns (default: `["*/*"]`)

  Results arrive via `handle_info` as `{:files, :picked, items}` or
  `{:files, :cancelled}`.

  Returns the socket unchanged.
  """
  @spec pick(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def pick(socket, opts \\ []) do
    types = Keyword.get(opts, :types, ["*/*"])
    types_json = :json.encode(types)
    Dala.Platform.Native.files_pick(types_json)
    socket
  end
end
