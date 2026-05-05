defmodule Dala.State do
  @moduledoc """
  Persistent key-value store for app state.

  Backed by `:dets` — Erlang's disk-based term storage, part of OTP stdlib.
  State survives app kills and restarts. Any Elixir term can be stored as a
  value; no serialisation step required.

  ## When to use this vs. Ecto

  - **`Dala.State`** — app preferences, UI choices, small per-user settings.
    Think: selected theme, onboarding complete flag, last-opened tab, cached
    user ID. Designed for O(dozens) of keys, not O(thousands) of rows.

  - **Your Ecto Repo** — user records, structured data, anything you'd query,
    filter, or paginate. Use migrations and schemas for that.

  ## Usage

      # Store anything — atoms, maps, lists, nested structures.
      Dala.State.put(:theme, :citrus)
      Dala.State.put(:onboarded, true)
      Dala.State.put(:last_position, %{lat: 43.7, lng: -79.4})

      # Read back on next launch — returns `default` if not yet set.
      Dala.State.get(:theme, :obsidian)   #=> :citrus
      Dala.State.get(:missing_key, 0)     #=> 0

      # Remove a key.
      Dala.State.delete(:last_position)

  ## Lifecycle

  Started automatically by `Dala.App.start/0` — no setup required.
  The backing file is stored at `dala_DATA_DIR/dala_state.dets` on device,
  or `priv/repo/dala_state.dets` in local dev (same directory as the SQLite DB).
  """

  use GenServer

  @table :dala_state

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Read a persisted value.

  Returns `default` if the key has never been written. `default` is `nil`
  unless explicitly provided.

      iex> Dala.State.get(:theme, :obsidian)
      :obsidian

      iex> Dala.State.put(:theme, :citrus)
      iex> Dala.State.get(:theme, :obsidian)
      :citrus

  Reads go directly to the underlying `:dets` table without going through
  the GenServer, so they never queue behind in-flight writes.
  """
  @spec get(term(), term()) :: term()
  def get(key, default \\ nil) do
    case :dets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  @doc """
  Persist a key-value pair to disk.

  Any Elixir term is accepted for both key and value. Backed by `:dets`
  (Erlang's disk-based term storage) with a `sync` after each write, so the
  value is on disk before this function returns and survives an immediate
  `SIGKILL` (Android OOM kill, iOS termination under memory pressure).

      Dala.State.put(:theme, :citrus)
      Dala.State.put(:onboarded, true)
      Dala.State.put({:last_seen, :home}, DateTime.utc_now())
      Dala.State.put(:prefs, %{font_size: 16, notifications: true})

  Calling `put/2` with an existing key overwrites the previous value.
  """
  @spec put(term(), term()) :: :ok
  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  @doc """
  Delete a key.

  No-op if the key is absent. The deletion is synchronised to disk before
  this function returns.

      Dala.State.delete(:theme)
      Dala.State.get(:theme, :obsidian)   #=> :obsidian
  """
  @spec delete(term()) :: :ok
  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    path = state_path() |> String.to_charlist()

    case :dets.open_file(@table, file: path, type: :set) do
      {:ok, _} -> {:ok, %{}}
      {:error, r} -> {:stop, {:dets_open_failed, r}}
    end
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    :ok = :dets.insert(@table, {key, value})
    :ok = :dets.sync(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    :ok = :dets.delete(@table, key)
    :ok = :dets.sync(@table)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.close(@table)
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp state_path do
    data_dir =
      System.get_env("dala_DATA_DIR") ||
        System.get_env("HOME") ||
        Path.join(File.cwd!(), "priv/repo")

    File.mkdir_p!(data_dir)
    Path.join(data_dir, "dala_state.dets")
  end
end
