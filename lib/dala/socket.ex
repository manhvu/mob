defmodule Dala.Socket do
  @moduledoc """
  The socket struct passed through all Dala.Screen and Dala.Component callbacks.

  Holds two things:
  - `assigns` — the public data map your `render/1` function reads from `@assigns`
  - `__dala__` — internal Dala metadata (screen module, platform, view refs, nav stack)

  You interact with a socket via `assign/2` and `assign/3`. Never mutate `__dala__`
  directly — it is an internal contract.
  """

  @type platform :: :android | :ios

  @type t :: %__MODULE__{
          assigns: map(),
          __dala__: %{
            screen: module() | nil,
            platform: platform(),
            root_view: term(),
            view_tree: map(),
            nav_stack: list(),
            nav_action: term()
          }
        }

  defstruct assigns: %{},
            __dala__: %{
              screen: nil,
              platform: :android,
              root_view: nil,
              view_tree: %{},
              nav_stack: [],
              nav_action: nil,
              # Track changed assigns - initialized here so pattern matching always works
              changed: MapSet.new()
            }

  @doc """
  Create a new socket for the given screen module.

  Options:
  - `:platform` — `:android` (default) or `:ios`
  """
  @spec new(module(), keyword()) :: t()
  def new(screen, opts \\ []) do
    platform = Keyword.get(opts, :platform, :android)

    %__MODULE__{
      assigns: %{},
      __dala__: %{
        screen: screen,
        platform: platform,
        root_view: nil,
        view_tree: %{},
        nav_stack: [],
        nav_action: nil,
        changed: MapSet.new()
      }
    }
  end

  @doc """
  Assign a single key/value pair into the socket's assigns.

      socket = assign(socket, :count, 0)
  """
  @spec assign(t(), atom(), term()) :: t()
  def assign(%__MODULE__{assigns: assigns, __dala__: dala} = socket, key, value)
      when is_atom(key) do
    # Track that this key changed
    changed = Map.get(dala, :changed, MapSet.new())
    changed = MapSet.put(changed, key)
    %{socket | assigns: Map.put(assigns, key, value), __dala__: Map.put(dala, :changed, changed)}
  end

  @doc """
  Assign multiple key/value pairs at once from a keyword list or map.

      socket = assign(socket, count: 0, name: "test")
      socket = assign(socket, %{count: 0})
  """
  @spec assign(t(), keyword() | map()) :: t()
  def assign(%__MODULE__{assigns: assigns, __dala__: dala} = socket, kw)
      when is_list(kw) or is_map(kw) do
    # Track which keys changed
    changed = Map.get(dala, :changed, MapSet.new())
    new_assigns = Map.new(kw)

    changed =
      Enum.reduce(Map.keys(new_assigns), changed, fn key, acc ->
        MapSet.put(acc, key)
      end)

    %{socket | assigns: Map.merge(assigns, new_assigns), __dala__: Map.put(dala, :changed, changed)}
  end

  @doc """
  Queue a push_screen navigation action.

  The screen process will process this on the next render cycle.
  """
  @spec push_screen(t(), module(), map()) :: t()
  def push_screen(%__MODULE__{__dala__: dala} = socket, dest, params \\ %{}) do
    %{socket | __dala__: Map.put(dala, :nav_action, {:push, dest, params})}
  end

  @doc """
  Queue a pop_screen navigation action.

  Pops the current screen from the navigation stack.
  """
  @spec pop_screen(t()) :: t()
  def pop_screen(%__MODULE__{__dala__: dala} = socket) do
    %{socket | __dala__: Map.put(dala, :nav_action, {:pop})}
  end

  @doc """
  Get a value from the internal `__dala__` metadata.

  Used internally by the screen process.
  """
  @spec get_dala(t(), atom()) :: term()
  def get_dala(%__MODULE__{__dala__: dala}, key) do
    Map.get(dala, key)
  end

  @doc """
  Put a value into the internal `__dala__` metadata.

  Used internally by the screen process.
  """
  @spec put_dala(t(), atom(), term()) :: t()
  def put_dala(%__MODULE__{__dala__: dala} = socket, key, value) do
    %{socket | __dala__: Map.put(dala, key, value)}
  end

  @doc """
  Store the root view ref returned by the renderer into `__dala__.root_view`.
  Called internally after the initial render.
  """
  @spec put_root_view(t(), term()) :: t()
  def put_root_view(%__MODULE__{__dala__: dala} = socket, view) do
    %{socket | __dala__: Map.put(dala, :root_view, view)}
  end

  @doc """
  Check if a specific key has changed since the last render.

  Returns `true` if the key was assigned since the last render.
  """
  @spec changed?(t(), atom()) :: boolean()
  def changed?(%__MODULE__{__dala__: dala}, key) do
    changed = Map.get(dala, :changed, MapSet.new())
    MapSet.member?(changed, key)
  end

  @doc """
  Clear the changed set after a render.

  Called internally after rendering to reset the change tracking.
  """
  @spec clear_changed(t()) :: t()
  def clear_changed(%__MODULE__{__dala__: dala} = socket) do
    %{socket | __dala__: Map.put(dala, :changed, MapSet.new())}
  end
end
