defmodule Dala.ML.Debug.Test do
  @moduledoc """
  Tests for Dala.ML.Debug — tensor inspection, profiling, and environment info.
  """

  use ExUnit.Case, async: true

  describe "tensor_info/1" do
    test "returns map with required keys" do
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      info = Dala.ML.Debug.tensor_info(tensor)

      assert Map.has_key?(info, :shape)
      assert Map.has_key?(info, :type)
      assert Map.has_key?(info, :size)
      assert Map.has_key?(info, :min)
      assert Map.has_key?(info, :max)
      assert Map.has_key?(info, :mean)
      assert Map.has_key?(info, :sample)
    end

    test "reports correct shape" do
      tensor = Nx.tensor([[1.0, 2.0], [3.0, 4.0]])
      info = Dala.ML.Debug.tensor_info(tensor)
      assert info.shape == {2, 2}
    end

    test "reports correct min/max" do
      tensor = Nx.tensor([5.0, 1.0, 3.0, 2.0, 4.0])
      info = Dala.ML.Debug.tensor_info(tensor)
      assert info.min == 1.0
      assert info.max == 5.0
    end

    test "reports correct mean" do
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      info = Dala.ML.Debug.tensor_info(tensor)
      assert info.mean == 2.0
    end

    test "sample contains up to 10 elements" do
      tensor = 1..100 |> Enum.to_list() |> Nx.tensor()
      info = Dala.ML.Debug.tensor_info(tensor)
      assert length(info.sample) <= 10
    end

    test "sample contains all elements for small tensors" do
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      info = Dala.ML.Debug.tensor_info(tensor)
      assert length(info.sample) == 3
    end
  end

  describe "profile/4" do
    test "returns timing statistics" do
      model =
        Axon.input("input", shape: {nil, 2})
        |> Axon.dense(1)

      {init_fn, _predict_fn} = Axon.build(model)
      params = init_fn.(Nx.template({1, 2}, :f32), %{})
      input = Nx.tensor([[1.0, 2.0]])

      result = Dala.ML.Debug.profile(model, params, input, iterations: 3, warmup: 1)

      assert Map.has_key?(result, :avg_ms)
      assert Map.has_key?(result, :min_ms)
      assert Map.has_key?(result, :max_ms)
      assert Map.has_key?(result, :p50_ms)
      assert Map.has_key?(result, :p95_ms)
      assert Map.has_key?(result, :p99_ms)
      assert Map.has_key?(result, :iterations)
      assert Map.has_key?(result, :backend)
    end

    test "timing values are non-negative floats" do
      model =
        Axon.input("input", shape: {nil, 2})
        |> Axon.dense(1)

      {init_fn, _predict_fn} = Axon.build(model)
      params = init_fn.(Nx.template({1, 2}, :f32), %{})
      input = Nx.tensor([[1.0, 2.0]])

      result = Dala.ML.Debug.profile(model, params, input, iterations: 3, warmup: 1)

      assert is_float(result.avg_ms)
      assert is_float(result.min_ms)
      assert is_float(result.max_ms)
      assert result.avg_ms >= 0.0
      assert result.min_ms >= 0.0
      assert result.max_ms >= 0.0
    end

    test "min <= avg <= max" do
      model =
        Axon.input("input", shape: {nil, 2})
        |> Axon.dense(1)

      {init_fn, _predict_fn} = Axon.build(model)
      params = init_fn.(Nx.template({1, 2}, :f32), %{})
      input = Nx.tensor([[1.0, 2.0]])

      result = Dala.ML.Debug.profile(model, params, input, iterations: 5, warmup: 1)

      assert result.min_ms <= result.avg_ms
      assert result.avg_ms <= result.max_ms
    end

    test "respects iterations option" do
      model =
        Axon.input("input", shape: {nil, 2})
        |> Axon.dense(1)

      {init_fn, _predict_fn} = Axon.build(model)
      params = init_fn.(Nx.template({1, 2}, :f32), %{})
      input = Nx.tensor([[1.0, 2.0]])

      result = Dala.ML.Debug.profile(model, params, input, iterations: 7, warmup: 1)
      assert result.iterations == 7
    end
  end

  describe "model_summary/1" do
    test "returns :ok" do
      model = Axon.input("input", shape: {nil, 10})
      assert Dala.ML.Debug.model_summary(model) == :ok
    end
  end

  describe "compare_outputs/3" do
    test "identical outputs match" do
      a = Nx.tensor([1.0, 2.0, 3.0])
      b = Nx.tensor([1.0, 2.0, 3.0])

      result = Dala.ML.Debug.compare_outputs(a, b)
      assert result.matches == true
      assert result.max_difference == 0.0
      assert result.mean_difference == 0.0
    end

    test "different outputs don't match" do
      a = Nx.tensor([1.0, 2.0, 3.0])
      b = Nx.tensor([1.0, 2.0, 4.0])

      result = Dala.ML.Debug.compare_outputs(a, b)
      assert result.matches == false
      assert result.max_difference > 0.0
    end

    test "respects custom tolerance" do
      a = Nx.tensor([1.0, 2.0, 3.0])
      b = Nx.tensor([1.001, 2.001, 3.001])

      # Default tolerance (1e-5) — should not match
      result_default = Dala.ML.Debug.compare_outputs(a, b)
      assert result_default.matches == false

      # Large tolerance — should match
      result_loose = Dala.ML.Debug.compare_outputs(a, b, tolerance: 0.01)
      assert result_loose.matches == true
    end

    test "returns required keys" do
      a = Nx.tensor([1.0])
      b = Nx.tensor([1.0])

      result = Dala.ML.Debug.compare_outputs(a, b)
      assert Map.has_key?(result, :max_difference)
      assert Map.has_key?(result, :mean_difference)
      assert Map.has_key?(result, :matches)
      assert Map.has_key?(result, :tolerance)
    end
  end

  describe "environment_info/0" do
    test "returns map with required keys" do
      info = Dala.ML.Debug.environment_info()

      assert Map.has_key?(info, :platform)
      assert Map.has_key?(info, :otp_version)
      assert Map.has_key?(info, :elixir_version)
      assert Map.has_key?(info, :nx_backend)
      assert Map.has_key?(info, :schedulers)
      assert Map.has_key?(info, :dirty_cpu_schedulers)
      assert Map.has_key?(info, :memory_mb)
    end

    test "otp_version is a string" do
      info = Dala.ML.Debug.environment_info()
      assert is_binary(info.otp_version)
    end

    test "elixir_version is a string" do
      info = Dala.ML.Debug.environment_info()
      assert is_binary(info.elixir_version)
    end

    test "memory_mb is a float" do
      info = Dala.ML.Debug.environment_info()
      assert is_float(info.memory_mb)
      assert info.memory_mb > 0.0
    end

    test "platform is a valid status map" do
      info = Dala.ML.Debug.environment_info()
      assert is_map(info.platform)
      assert Map.has_key?(info.platform, :platform)
    end
  end
end
