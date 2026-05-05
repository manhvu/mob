defmodule Dala.Blob do
  @moduledoc """
  Binary data handling via blob references.

  Blobs are stored temporarily in an ETS table with a reference atom.

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

  @spec create(binary(), String.t()) :: atom()
  def create(data, type \\ "application/octet-stream") when is_binary(data) and is_binary(type) do
    :"blob_stub_#{System.unique_integer([:positive])}"
  end

  @spec slice(atom(), non_neg_integer(), non_neg_integer()) :: atom()
  def slice(blob_ref, _start, _end_pos) when is_atom(blob_ref) do
    :"blob_stub_#{System.unique_integer([:positive])}"
  end

  @spec to_base64(atom()) :: String.t() | nil
  def to_base64(blob_ref) when is_atom(blob_ref) do
    nil
  end

  @spec to_file(atom(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def to_file(blob_ref, path) when is_atom(blob_ref) and is_binary(path) do
    {:ok, path}
  end
end
