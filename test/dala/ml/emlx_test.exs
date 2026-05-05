defmodule Dala.ML.EMLXTest do
  use ExUnit.Case, async: true
  import Dala.ML.EMLX

  @moduledoc """
  Tests for Dala.ML.EMLX zero-config setup.

  Note: Full tests require iOS device/simulator.
  These tests verify the API structure and non-iOS behavior.
  """

  describe "setup/0" do
    test "returns :ok on non-iOS platforms" do
      # On non-iOS, setup should return :ok (no-op)
      if not (ios_device?() or ios_simulator?()) do
        assert {:ok, _} = setup()
      end
    end

    test "returns :ok tuple structure" do
      result = setup()
      assert {:ok, _} = result
    end
  end

  describe "platform detection" do
    test "ios_device?/0 returns boolean" do
      result = ios_device?()
      assert is_boolean(result)
    end

    test "ios_simulator?/0 returns boolean" do
      result = ios_simulator?()
      assert is_boolean(result)
    end
  end

  describe "platform_config/0" do
    test "returns config map with required keys" do
      config = platform_config()
      assert is_map(config)
      assert Map.has_key?(config, :jit_enabled)
      assert Map.has_key?(config, :device)
    end

    test "jit_enabled is boolean" do
      config = platform_config()
      assert is_boolean(config.jit_enabled)
    end

    test "device is an atom" do
      config = platform_config()
      assert is_atom(config.device)
    end
  end

  describe "integration with Nx" do
    test "Nx backend can be configured" do
      # This test verifies the API works (actual backend depends on platform)
      setup()

      # Verify Nx is available
      assert Code.ensure_loaded?(Nx)
    end
  end

  # Helper functions
  defp check_boolean(val) do
    val == true or val == false
  end

  defp check_atom(val) do
    is_atom(val)
  end
end
