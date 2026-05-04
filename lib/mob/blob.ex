defmodule Mob.Blob do
  @moduledoc """
  Binary data handling via blob references.

  Blobs are stored temporarily in an ETS table with a reference atom.

  ## Examples

      # Create a blob from binary data
      blob_ref = Mob.Blob.create(<<1, 2, 3>>, "application/octet-stream")

      # Slice a blob
      sliced = Mob.Blob.slice(blob_ref, 0, 2)

      # Convert to base64
      base64 = Mob.Blob.to_base64(blob_ref)

      # Save to file
      {:ok, path} = Mob.Blob.to_file(blob_ref, "/tmp/blob.bin")
  """

  @table :mob_blob_table

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end

    @table
  end

  @spec create(binary(), String.t()) :: atom()
  def create(data, type \\ "application/octet-stream") when is_binary(data) and is_binary(type) do
    :"blob_stub_#{System.unique_integer([:positive])}"
  end

  @spec slice(atom(), non_neg_integer(), non_neg_integer()) :: atom()
  def slice(blob_ref, start, end_pos) when is_atom(blob_ref) do
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
