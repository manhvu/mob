defmodule Dala.ML.ONNX.Test do
  @moduledoc """
  Tests for Dala.ML.ONNX.

  Note: These tests only run on platforms with ONNX Runtime available.
  On unsupported platforms, they will return `:not_supported`.
  """

  use ExUnit.Case, async: true

  @tag :onnx_only
  test "create_session returns session_id or error" do
    # Dummy model data (not a real ONNX model)
    dummy_data = <<1, 2, 3, 4, 5, 6, 7, 8>>

    case Dala.ML.ONNX.create_session(dummy_data) do
      {:ok, session_id} when is_integer(session_id) ->
        # Clean up
        Dala.ML.ONNX.destroy_session(session_id)
        :ok

      :not_supported ->
        :ok

      {:error, _} ->
        :ok
    end
  end

  test "ONNX module is available" do
    assert Code.ensure_loaded?(Dala.ML.ONNX)
  end

  test "available? returns boolean or not_supported" do
    result = Dala.ML.ONNX.available?()
    assert result in [true, false, :not_supported]
  end
end
