defmodule Dala.StateTest do
  use ExUnit.Case, async: false

  # Each test uses an isolated DETS file so tests don't share state.
  setup do
    tmp = Path.join(System.tmp_dir!(), "dala_state_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    System.put_env("dala_DATA_DIR", tmp)

    on_exit(fn ->
      System.delete_env("dala_DATA_DIR")
      # Close the DETS table if still open, then clean up.
      :dets.close(:dala_state)
      File.rm_rf!(tmp)
    end)

    # Stop any running State process from a prior test.
    case Process.whereis(Dala.State) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    {:ok, _} = Dala.State.start_link()
    :ok
  end

  describe "get/2" do
    test "returns default when key is absent" do
      assert Dala.State.get(:missing) == nil
      assert Dala.State.get(:missing, :fallback) == :fallback
    end

    test "returns stored value after put" do
      Dala.State.put(:counter, 42)
      assert Dala.State.get(:counter) == 42
    end

    test "stores arbitrary terms — maps, lists, atoms" do
      Dala.State.put(:prefs, %{theme: :citrus, font_size: 16})
      assert Dala.State.get(:prefs) == %{theme: :citrus, font_size: 16}

      Dala.State.put(:tags, [:a, :b, :c])
      assert Dala.State.get(:tags) == [:a, :b, :c]
    end
  end

  describe "put/2" do
    test "overwrites existing value" do
      Dala.State.put(:x, 1)
      Dala.State.put(:x, 2)
      assert Dala.State.get(:x) == 2
    end

    test "persists across clean process stop" do
      Dala.State.put(:survived, true)
      pid = Process.whereis(Dala.State)
      GenServer.stop(pid)
      {:ok, _} = Dala.State.start_link()
      assert Dala.State.get(:survived) == true
    end

    test "persists across abrupt kill (SIGKILL simulation — no terminate callback)" do
      # dets.sync/1 is called after every write so data is on disk even when
      # the GenServer is killed before its terminate/2 can run dets.close/1.
      Dala.State.put(:kill_survived, :yes)
      pid = Process.whereis(Dala.State)
      # don't cascade the kill to the test process
      Process.unlink(pid)
      # bypasses terminate/2, no dets.close
      Process.exit(pid, :kill)
      Process.sleep(10)
      {:ok, _} = Dala.State.start_link()
      assert Dala.State.get(:kill_survived) == :yes
    end
  end

  describe "delete/1" do
    test "removes the key" do
      Dala.State.put(:temp, "ephemeral")
      Dala.State.delete(:temp)
      assert Dala.State.get(:temp) == nil
    end

    test "is a no-op for absent keys" do
      assert Dala.State.delete(:nonexistent) == :ok
    end
  end
end
