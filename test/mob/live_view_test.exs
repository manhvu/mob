defmodule Mob.LiveViewTest do
  use ExUnit.Case, async: true

  # ── local_url/1 ───────────────────────────────────────────────────────────

  describe "local_url/1" do
    setup do
      # Preserve any existing env value and restore after each test
      original = Application.get_env(:mob, :liveview_port)

      on_exit(fn ->
        if original do
          Application.put_env(:mob, :liveview_port, original)
        else
          Application.delete_env(:mob, :liveview_port)
        end
      end)

      :ok
    end

    test "defaults to port 4000" do
      Application.delete_env(:mob, :liveview_port)
      assert Mob.LiveView.local_url("/") == "http://127.0.0.1:4000/"
    end

    test "uses configured port" do
      Application.put_env(:mob, :liveview_port, 4001)
      assert Mob.LiveView.local_url("/") == "http://127.0.0.1:4001/"
    end

    test "appends path" do
      Application.delete_env(:mob, :liveview_port)
      assert Mob.LiveView.local_url("/dashboard") == "http://127.0.0.1:4000/dashboard"
    end

    test "defaults path to /" do
      Application.delete_env(:mob, :liveview_port)
      assert Mob.LiveView.local_url() == "http://127.0.0.1:4000/"
    end

    test "always uses 127.0.0.1 loopback" do
      url = Mob.LiveView.local_url("/any")
      assert String.starts_with?(url, "http://127.0.0.1:")
    end

    test "port 8080 example" do
      Application.put_env(:mob, :liveview_port, 8080)
      assert Mob.LiveView.local_url("/settings") == "http://127.0.0.1:8080/settings"
    end
  end
end
