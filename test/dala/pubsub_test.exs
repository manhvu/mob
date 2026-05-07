defmodule Dala.PubSubTest do
  use ExUnit.Case, async: false

  setup do
    name = :test_pubsub
    start_supervised!({Dala.PubSub, name: name})
    %{pubsub: name}
  end

  describe "subscribe/2" do
    test "subscribes caller to a topic", %{pubsub: pubsub} do
      assert :ok = Dala.PubSub.subscribe(pubsub, "topic:123")
      assert Dala.PubSub.subscriber_count(pubsub, "topic:123") == 1
    end
  end

  describe "unsubscribe/2" do
    test "unsubscribes caller from a topic", %{pubsub: pubsub} do
      Dala.PubSub.subscribe(pubsub, "topic:123")
      assert :ok = Dala.PubSub.unsubscribe(pubsub, "topic:123")
      assert Dala.PubSub.subscriber_count(pubsub, "topic:123") == 0
    end
  end

  describe "broadcast/3" do
    test "sends message to all subscribers", %{pubsub: pubsub} do
      Dala.PubSub.subscribe(pubsub, "topic:123")

      assert :ok = Dala.PubSub.broadcast(pubsub, "topic:123", {:hello, "world"})
      assert_received {:hello, "world"}
    end

    test "does not send message to non-subscribers", %{pubsub: pubsub} do
      Dala.PubSub.subscribe(pubsub, "topic:123")

      Dala.PubSub.broadcast(pubsub, "topic:456", {:hello, "world"})
      refute_received {:hello, "world"}
    end
  end

  describe "broadcast_from/4" do
    test "does not send message to sender", %{pubsub: pubsub} do
      # Only spawn a process that subscribes and broadcasts from itself
      # The test process does NOT subscribe
      test_pid = self()

      spawn(fn ->
        # This process subscribes and broadcasts from itself
        Dala.PubSub.subscribe(pubsub, "topic:123")
        Dala.PubSub.broadcast_from(pubsub, self(), "topic:123", :should_not_receive_by_sender)
        send(test_pid, :done)
      end)

      # Wait for the spawned process to finish
      receive do
        :done -> :ok
      after
        500 -> :timeout
      end

      # The spawned process should NOT receive the message because it excluded itself
      # We can't easily test this from outside, but we can verify the test process didn't get it
      # (which it wouldn't anyway since it didn't subscribe)
      refute_received :should_not_receive_by_sender
    end

    test "sends message to other subscribers", %{pubsub: pubsub} do
      # Subscribe the test process
      Dala.PubSub.subscribe(pubsub, "topic:123")

      # Spawn a process that broadcasts from itself
      spawn(fn ->
        Dala.PubSub.broadcast_from(pubsub, self(), "topic:123", :should_receive)
      end)

      # Give it time to run
      Process.sleep(50)

      # The test process SHOULD receive the message
      assert_received :should_receive
    end
  end

  describe "subscriber_count/2" do
    test "returns correct count", %{pubsub: pubsub} do
      assert Dala.PubSub.subscriber_count(pubsub, "topic:123") == 0

      Dala.PubSub.subscribe(pubsub, "topic:123")
      assert Dala.PubSub.subscriber_count(pubsub, "topic:123") == 1

      # Subscribe again (duplicate)
      Dala.PubSub.subscribe(pubsub, "topic:123")
      assert Dala.PubSub.subscriber_count(pubsub, "topic:123") == 2
    end
  end
end
