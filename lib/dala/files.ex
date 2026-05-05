defmodule Dala.Files do
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

  @spec pick(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def pick(socket, opts \\ []) do
    types = Keyword.get(opts, :types, ["*/*"])
    types_json = :json.encode(types)
    :dala_nif.files_pick(types_json)
    socket
  end
end
