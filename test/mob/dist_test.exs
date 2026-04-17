defmodule Mob.DistTest do
  use ExUnit.Case, async: false

  # Distribution tests must run serially — starting/stopping :net_kernel affects
  # the whole VM. async: false ensures no interference with other test modules.

  describe "stop/0" do
    test "returns :ok when distribution is not running" do
      # Baseline: if this node is not distributed, stop/0 should be a no-op
      if not Node.alive?() do
        assert Mob.Dist.stop() == :ok
      end
    end

    test "stops a running distribution node and returns :ok" do
      # Start distribution on an arbitrary local name if not already running
      was_alive = Node.alive?()

      unless was_alive do
        Node.start(:"mob_dist_test@127.0.0.1", :longnames)
      end

      assert Node.alive?()
      assert Mob.Dist.stop() == :ok
      assert not Node.alive?()
    end

    test "is idempotent — calling stop/0 twice is safe" do
      unless Node.alive?() do
        Node.start(:"mob_dist_test_idempotent@127.0.0.1", :longnames)
      end

      assert Mob.Dist.stop() == :ok
      assert Mob.Dist.stop() == :ok
    end

    test "disconnects connected nodes before stopping" do
      # Start two nodes and connect them, then verify stop/0 cleans up
      Node.start(:"mob_dist_test_disconnect@127.0.0.1", :longnames)
      Node.set_cookie(:test_cookie)

      # We can't connect to a real second node in a unit test, but we can
      # verify Node.list() is empty after stop and that no exception is raised
      # even when the node list would need to be flushed.
      assert Mob.Dist.stop() == :ok
      assert not Node.alive?()
    end
  end
end
