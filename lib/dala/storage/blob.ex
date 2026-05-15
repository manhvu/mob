defmodule Dala.Storage.Blob do
  @moduledoc """
  Binary data handling via blob references.

  Blobs are stored in native memory and referenced by an opaque handle.

  ## Examples

      # Create a blob from binary data
      blob_ref = Dala.Storage.Blob.create(<<1, 2, 3>>, "application/octet-stream")

      # Slice a blob
      sliced = Dala.Blob.slice(blob_ref, 0, 2)

      # Convert to base64
      base64 = Dala.Blob.to_base64(blob_ref)

      # Save to file
      {:ok, path} = Dala.Blob.to_file(blob_ref, "/tmp/blob.bin")
  """

  @doc """
  Create a blob from binary data.

  `type` is the MIME type (default: `"application/octet-stream"`).
  Returns an opaque blob reference.
  """
  @spec create(binary(), String.t()) :: term()
  def create(data, type \\ "application/octet-stream") when is_binary(data) and is_binary(type) do
    Dala.Platform.Native.blob_create(data, type)
  end

  @doc """
  Slice a blob from `start_pos` to `end_pos`.
  Returns a new blob reference.
  """
  @spec slice(term(), non_neg_integer(), non_neg_integer()) :: term()
  def slice(blob_ref, start_pos, end_pos) do
    Dala.Platform.Native.blob_slice(blob_ref, start_pos, end_pos)
  end

  @doc "Convert a blob to a base64-encoded string. Returns `nil` if the blob is invalid."
  @spec to_base64(term()) :: String.t() | nil
  def to_base64(blob_ref) do
    Dala.Platform.Native.blob_to_base64(blob_ref)
  end

  @doc "Save blob contents to a file at the given path."
  @spec to_file(term(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def to_file(blob_ref, path) when is_binary(path) do
    Dala.Platform.Native.blob_to_file(blob_ref, path)
  end
end
