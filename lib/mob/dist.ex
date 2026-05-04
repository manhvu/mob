defmodule Mob.Dist do
  @moduledoc """
  Platform-aware Erlang distribution startup.

  On iOS, distribution is started at BEAM launch via flags in mob_beam.m
  (`-name mob_demo@127.0.0.1`), so nothing extra is needed here.

  On Android, starting distribution at BEAM launch races with Android's hwui
  thread pool initialization (~125ms window), corrupting an internal mutex and
  causing a SIGABRT. The fix is to defer `Node.start/2` until after the UI has
  fully settled.

  Additionally, `mix mob.connect` runs `adb reverse tcp:4369 tcp:4369` to tunnel
  Mac EPMD into the device. OTP's `Node.start/2` would ordinarily spawn a local
  `epmd` daemon that also tries to bind port 4369 — causing a port conflict and
  crash. The fix: set `start_epmd: false` and wait for the ADB-tunnelled EPMD to
  be reachable before calling `Node.start/2`. If the tunnel is not up within 10s
  (standalone launch, no `mix mob.connect`), distribution is skipped gracefully.

  ## Usage (in your app's start/0)

      # ⚠️ NEVER use hardcoded cookies in production!
      # Generate a secure cookie per app and store it securely.
      cookie = Mob.Dist.cookie_from_env("MY_APP_DIST_COOKIE", "my_app")
      Mob.Dist.ensure_started(node: :"my_app@127.0.0.1", cookie: cookie)

  Options:
  - `:node`   — node name atom, e.g. `:"mob_demo@127.0.0.1"` (required on Android)
  - `:cookie` — cookie atom (required on Android) — use `cookie_from_env/2`
  - `:delay`  — ms to wait before starting dist on Android (default: 3_000)
  """

  @default_delay 3_000

  @doc """
  Generate a secure distribution cookie from environment or derive from app name.

  Looks up `env_var` first; if not set, derives a deterministic cookie from
  the `app_name` string using a hash. The derived cookie is *not* cryptographically
  random — it just avoids the worst practice of hardcoded atoms like `:secret`.

  For production, **always set the environment variable** to a strong random value:

      # Generate with: openssl rand -hex 32
      MY_APP_DIST_COOKIE=9f3a... mix mob.deploy

  Examples:

      # From env (recommended):
      cookie = Mob.Dist.cookie_from_env("MY_APP_DIST_COOKIE", "my_app")

      # Fallback (development only):
      cookie = Mob.Dist.cookie_from_env("MY_APP_DIST_COOKIE", :my_app)

  """
  @spec cookie_from_env(String.t(), atom() | String.t()) :: atom()
  def cookie_from_env(env_var, app_name) when is_atom(app_name) do
    cookie_from_env(env_var, Atom.to_string(app_name))
  end

  def cookie_from_env(env_var, app_name) when is_binary(app_name) do
    case System.get_env(env_var) do
      nil ->
        # Development fallback: derive from app name
        :mob_nif.log("Mob.Dist: no " <> env_var <> " set, deriving cookie from app name")
        :crypto.hash(:sha256, app_name) |> Base.encode16() |> String.to_atom()

      cookie_str ->
        String.to_atom(cookie_str)
    end
  end

  @doc """
  Ensure Erlang distribution is running for the current platform.

  - iOS: no-op (dist already started via BEAM args in mob_beam.m).
  - Android: spawns a process that sleeps for `:delay` ms then calls
    `Node.start/2` + `Node.set_cookie/1`. Pins the dist port to `:dist_port`
    (default 9100) so `dev_connect.sh` knows which port to forward.

  Options:
  - `:node`      — base node name atom (required on Android)
  - `:cookie`    — cookie atom (required on Android)
  - `:delay`     — ms to wait before starting dist (default: 3_000)
  - `:dist_port` — Erlang dist listen port (default: 9100)

  ## Per-device node names (Android)

  Mac's EPMD only allows one registration per name. Two phones running the
  same app with the same hardcoded `:node` collide — the second to start
  gets `:nodistribution` and silently runs without dist. To keep two or
  more devices distinguishable, set the `MOB_NODE_SUFFIX` env var (the
  Android shell launcher reads `mob_node_suffix` from the launch intent
  extras and exports it). When present, the resolved node becomes
  `<base_name>_<suffix>@<host>` — e.g. `test_nif_android_zy22cr@127.0.0.1`.

  ## Security notes

  - **Never commit distribution cookies** to source control.
  - **Never use hardcoded atoms** like `:secret` or `:mob_secret` in production.
  - Store cookies in environment variables or secure key storage.
  - Rotate cookies periodically using `Node.set_cookie/1`.
  - The `Mob.Diag` module is a permanent target if credentials leak —
    see `Mob.Diag` docs for mitigation strategies.
  """
  @spec ensure_started(keyword()) :: :ok
  def ensure_started(opts \\ []) do
    cond do
      release_mode?() ->
        # App Store / TestFlight build: distribution is disabled at the C
        # layer (mob_beam.m drops -name/-setcookie when MOB_RELEASE is
        # defined). Skip Node.start so calling apps don't have to special-case
        # release vs dev — same call site, no-ops in release.
        :ok

      true ->
        case :mob_nif.platform() do
          :ios ->
            :ok

          :android ->
            base_node = Keyword.fetch!(opts, :node)
            cookie = Keyword.fetch!(opts, :cookie)
            delay = Keyword.get(opts, :delay, @default_delay)
            dist_port = Keyword.get(opts, :dist_port, 9100)
            node = apply_suffix(base_node, System.get_env("MOB_NODE_SUFFIX"))

            if node != base_node do
              :mob_nif.log("Mob.Dist: node suffix applied — #{base_node} → #{node}")
            end

            spawn(fn -> start_after(node, cookie, delay, dist_port) end)
            :ok
        end
    end
  end

  @doc false
  def release_mode?, do: System.get_env("MOB_RELEASE") == "1"

  @doc false
  @spec apply_suffix(node(), String.t() | nil) :: node()
  def apply_suffix(base_node, nil), do: base_node
  def apply_suffix(base_node, ""), do: base_node

  def apply_suffix(base_node, suffix) when is_binary(suffix) do
    suffix = String.trim(suffix)

    if suffix == "" do
      base_node
    else
      case String.split(Atom.to_string(base_node), "@", parts: 2) do
        [name, host] -> :"#{name}_#{suffix}@#{host}"
        [name] -> :"#{name}_#{suffix}"
      end
    end
  end

  @doc """
  Stop Erlang distribution and shut down EPMD.

  Disconnects all connected nodes, stops the distribution listener, and
  terminates the local EPMD daemon if one was started by this node.

  Intended for use after an OTA update session or when forming a `Mob.Cluster`
  connection that should not persist. The app continues running normally after
  calling `stop/0` — only remote connectivity is removed.

  Returns `:ok` whether or not distribution was running.

      # OTA update session
      Mob.Dist.ensure_started(node: :"my_app@127.0.0.1", cookie: session_cookie)
      Node.connect(update_server_node)
      # ... receive BEAMs ...
      Mob.Dist.stop()

      # Mob.Cluster — rotate cookie between sessions
      Node.set_cookie(new_session_cookie)   # no restart needed
  """
  @spec stop() :: :ok
  def stop do
    if Node.alive?() do
      Enum.each(Node.list(), &Node.disconnect/1)
      :net_kernel.stop()
    end

    :ok
  end

  defp start_after(node, cookie, delay, dist_port) do
    Process.sleep(delay)
    # Wait for EPMD on port 4369 before starting distribution.
    #
    # When `mix mob.connect` is running, it sets up `adb reverse tcp:4369 tcp:4369`
    # which forwards device:4369 → Mac EPMD. We must not spawn a local epmd (which
    # would also try to bind 4369), so we set start_epmd: false and wait for the
    # Mac's EPMD to be reachable via the ADB tunnel.
    #
    # Without the tunnel (standalone launch), EPMD will never appear on 4369 and
    # we skip distribution entirely — the app runs fine, just not debuggable remotely.
    :mob_nif.log("Mob.Dist: waiting for EPMD (adb reverse tcp:4369 tcp:4369)...")

    case wait_for_epmd(10_000) do
      :ready ->
        :mob_nif.log("Mob.Dist: EPMD reachable, starting dist")
        # OTP auth tries to write HOME/.config/erlang/.erlang.cookie — ensure the dir exists.
        home = System.get_env("HOME") || "/data/data/com.mob.demo/files"
        File.mkdir_p("#{home}/.config/erlang")
        # Prevent OTP from spawning a local epmd daemon — the Mac's EPMD is available
        # via the ADB reverse tunnel and we must not fight it for port 4369.
        :application.set_env(:kernel, :start_epmd, false)
        # Pin the dist port so dev_connect.sh knows which port to adb-forward.
        :application.set_env(:kernel, :inet_dist_listen_min, dist_port)
        :application.set_env(:kernel, :inet_dist_listen_max, dist_port)
        result = Node.start(node, :longnames)
        :mob_nif.log("Mob.Dist: result=#{inspect(result)}")

        case result do
          {:ok, _} ->
            Node.set_cookie(cookie)
            :mob_nif.log("Mob.Dist: distribution started")

          _ ->
            :ok
        end

      :timeout ->
        :mob_nif.log(
          "Mob.Dist: no EPMD on port 4369 after 10s -- skipping dist (run mix mob.connect to enable)"
        )
    end
  end

  # Poll port 4369 until the ADB-tunnelled Mac EPMD responds or we time out.
  defp wait_for_epmd(remaining_ms) when remaining_ms <= 0, do: :timeout

  defp wait_for_epmd(remaining_ms) do
    case :gen_tcp.connect({127, 0, 0, 1}, 4369, [], 200) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        :ready

      {:error, _} ->
        Process.sleep(500)
        wait_for_epmd(remaining_ms - 700)
    end
  end
end
