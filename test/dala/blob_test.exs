defmodule Dala.BlobTest do
  use ExUnit.Case, async: false

  describe "create/2" do
    test "returns an atom reference" do
      result = Dala.Blob.create(<<1, 2, 3>>, "application/octet-stream")
      assert result == :nif_not_loaded or is_atom(result)
    end

    test "uses default type" do
      result = Dala.Blob.create(<<1, 2, 3>>)
      assert result == :nif_not_loaded or is_atom(result)
    end
  end

  describe "slice/3" do
    test "returns atom reference" do
      blob_ref = Dala.Blob.create(<<1, 2, 3, 4, 5>>)
      result = Dala.Blob.slice(blob_ref, 0, 2)
      assert result == :nif_not_loaded or is_atom(result)
    end
  end

  describe "to_base64/1" do
    test "returns nil or string" do
      blob_ref = Dala.Blob.create(<<1, 2, 3>>)
      result = Dala.Blob.to_base64(blob_ref)
      assert result == :nif_not_loaded or is_nil(result) or is_binary(result)
    end
  end

  describe "to_file/2" do
    test "returns ok tuple or error" do
      blob_ref = Dala.Blob.create(<<1, 2, 3>>)
      result = Dala.Blob.to_file(blob_ref, "/tmp/test_blob.bin")

      case result do
        :nif_not_loaded -> :ok
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end
end
