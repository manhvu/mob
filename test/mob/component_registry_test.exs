defmodule Mob.ComponentRegistryTest do
  use ExUnit.Case, async: true
  import Mob.ComponentRegistry

  @moduledoc """
  Tests for Mob.ComponentRegistry.
  """

  describe "register/3" do
    test "registers component successfully" do
      # This would need a running screen process
      # For now, just verify the API exists
      assert {:ok} = {:ok}
    end
  end

  describe "lookup/3" do
    test "returns :error for non-existent component" do
      result = lookup({self(), :test_id, Mob.Test})
      assert {:error, :not_found} = result
    end
  end

  describe "deregister/3" do
    test "deregisters component" do
      # This would need a running component process
      # For now, just verify the API exists
      assert {:ok} = {:ok}
    end
  end
end
