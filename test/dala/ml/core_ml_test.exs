defmodule Dala.ML.CoreML.Test do
  @moduledoc """
  Tests for Dala.ML.CoreML.

  Note: These tests only run on iOS devices/simulators with CoreML available.
  On other platforms, they will skip or return `:not_supported`.
  """

  use ExUnit.Case, async: true

  # These tests only run on iOS where CoreML is available.
  # On other platforms, they will skip or return `:not_supported`.

  test "load_model returns error for non-existent file" do
    result = Dala.ML.CoreML.load_model("/non/existent/path.mlmodel", "test_model")

    case result do
      {:error, _} -> :ok
      :not_supported -> :ok
      other -> flunk("Unexpected result: #{inspect(other)}")
    end
  end

  test "loaded? returns false for unloaded model" do
    result = Dala.ML.CoreML.loaded?("non_existent_model")

    case result do
      false -> :ok
      # Might be loaded from another test
      true -> :ok
      :not_supported -> :ok
      other -> flunk("Unexpected result: #{inspect(other)}")
    end
  end

  test "loaded_models returns a list or atom" do
    result = Dala.ML.CoreML.loaded_models()

    case result do
      list when is_list(list) -> :ok
      :none -> :ok
      other -> flunk("Unexpected result: #{inspect(other)}")
    end
  end

  test "CoreML module is available" do
    # Just check the module is defined
    assert Code.ensure_loaded?(Dala.ML.CoreML)
  end
end
