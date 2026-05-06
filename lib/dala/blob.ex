defmodule Dala.Blob do
  @moduledoc """
  Binary data handling via blob references.

  Blobs are stored in native memory and referenced by an opaque handle.

  ## Examples

      # Create a blob from binary data
      blob_ref = Dala.Blob.create(<<1, 2, 3>>, "application/octet-stream")

      # Slice a blob
      sliced = Dala.Blob.slice(blob_ref, 0, 2)

      # Convert to base64
      base64 = Dala.Blob.to_base64(blob_ref)

      # Save to file
      {:ok, path} = Dala.Blob.to_file(blob_ref, "/tmp/blob.bin")
  """

  @spec create(binary(), String.t()) :: term()
  def create(data, type \\ "application/octet-stream") when is_binary(data) and is_binary(type) do
    Dala.Native.blob_create(data, type)
  end

  @spec slice(term(), non_neg_integer(), non_neg_integer()) :: term()
  def slice(blob_ref, start_pos, end_pos) do
    Dala.Native.blob_slice(blob_ref, start_pos, end_pos)
  end

  @spec to_base64(term()) :: String.t() | nil
  def to_base64(blob_ref) do
    Dala.Native.blob_to_base64(blob_ref)
  end

  @spec to_file(term(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def to_file(blob_ref, path) when is_binary(path) do
    Dala.Native.blob_to_file(blob_ref, path)
  end
end
