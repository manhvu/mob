# Screen Lifecycle

A Mob screen is a GenServer wrapped by `Mob.Screen`. Each screen in the navigation stack is a separate, supervised process. Understanding the lifecycle means understanding when each callback fires and what you can do in it.

## Callbacks

### `mount/3`

```elixir
@callback mount(params :: map(), session :: map(), socket :: Mob.Socket.t()) ::
  {:ok, Mob.Socket.t()} | {:error, term()}
```

Called once when the screen process starts. Initialize your assigns here.

`params` comes from the navigation call that opened this screen:

```elixir
# Screen A navigates to Screen B with params:
Mob.Socket.push_screen(socket, MyApp.DetailScreen, %{id: 42})

# Screen B receives them in mount:
def mount(%{id: id}, _session, socket) do
  item = fetch_item(id)
  {:ok, Mob.Socket.assign(socket, :item, item)}
end
```

`session` is reserved for future use; pass it through.

If `mount/3` returns `{:error, reason}`, the GenServer stops with that reason.

### `render/1`

```elixir
@callback render(assigns :: map()) :: map()
```

Returns the component tree as a plain Elixir map. Called after every callback that returns a modified socket. The renderer serialises the tree, resolves tokens, and calls the NIF — Compose or SwiftUI diffs and updates the display.

Keep `render/1` pure. No side effects, no process sends. It may be called more than once for a given state.

```elixir
def render(assigns) do
  %{
    type: :column,
    props: %{padding: :space_md, background: :background},
    children: [
      %{type: :text,   props: %{text: assigns.title, text_size: :xl, text_color: :on_background}, children: []},
      %{type: :button, props: %{text: "Save",        on_tap: {self(), :save}},                    children: []}
    ]
  }
end
```

### `handle_event/3`

```elixir
@callback handle_event(event :: String.t(), params :: map(), socket :: Mob.Socket.t()) ::
  {:noreply, Mob.Socket.t()} | {:reply, map(), socket :: Mob.Socket.t()}
```

Fires when the user interacts with a UI component. The `event` string and `params` map come from the native layer.

For tap events, the event is `"tap"` and params include `"tag"` when you used a tagged `on_tap`:

```elixir
# In render:
on_tap: {self(), :save}

# In handle_event:
def handle_event("tap", %{"tag" => "save"}, socket) do
  save_data(socket.assigns)
  {:noreply, socket}
end
```

For text fields, `on_change` fires with `%{"value" => new_text}`:

```elixir
# In render:
on_change: {self(), :name_changed}

# In handle_event:
def handle_event("tap", %{"tag" => "name_changed", "value" => value}, socket) do
  {:noreply, Mob.Socket.assign(socket, :name, value)}
end
```

The default implementation (from `use Mob.Screen`) raises for any unhandled event. Add `handle_event/3` clauses for every interaction your screen supports.

Navigation is triggered by returning a modified socket:

```elixir
def handle_event("tap", %{"tag" => "open_detail"}, socket) do
  {:noreply, Mob.Socket.push_screen(socket, MyApp.DetailScreen, %{id: socket.assigns.id})}
end
```

### `handle_info/2`

```elixir
@callback handle_info(message :: term(), socket :: Mob.Socket.t()) ::
  {:noreply, Mob.Socket.t()}
```

Handles all other messages sent to the screen process — results from device APIs, push notifications, PubSub broadcasts, timer messages, and anything sent via `send/2`.

Device APIs are always async: call the API, then handle the result in `handle_info/2`:

```elixir
def handle_event("tap", %{"tag" => "take_photo"}, socket) do
  # Request permission first if not already granted
  socket = Mob.Camera.capture_photo(socket)
  {:noreply, socket}
end

def handle_info({:camera, :photo, %{path: path}}, socket) do
  {:noreply, Mob.Socket.assign(socket, :photo_path, path)}
end

def handle_info({:camera, :cancelled}, socket) do
  {:noreply, socket}
end
```

The default implementation (from `use Mob.Screen`) is a no-op that returns the socket unchanged. Override only the messages you care about.

### `terminate/2`

```elixir
@callback terminate(reason :: term(), socket :: Mob.Socket.t()) :: term()
```

Called when the screen process is about to stop. Use it for cleanup — cancel timers, release resources. The return value is ignored.

The default is a no-op. Most screens don't need to implement this.

## Lifecycle flow

```
start_root/2 or push_screen/2
        │
        ▼
   mount/3  ──────────────────────────────────────────────┐
        │                                                  │
        ▼                                                  │
   render/1  ─ NIF set_root / set_view                    │
        │                                                  │
        ├── user taps button ────► handle_event/3 ──► render/1
        │                                                  │
        ├── device API result ───► handle_info/2  ──► render/1
        │                                                  │
        ├── send(pid, msg)  ──────► handle_info/2  ──► render/1
        │                                                  │
        └── screen popped from stack ─► terminate/2  ──────┘
```

## The socket

All callbacks receive and return a `Mob.Socket.t()`. Think of it as a struct carrying your screen's state:

- `socket.assigns` — your data (`:count`, `:user`, `:items`, etc.)
- `socket.__mob__` — internal framework state; do not touch directly

Use `Mob.Socket.assign/2,3` to update assigns. Use the navigation functions (`push_screen`, `pop_screen`, etc.) to queue navigation actions. Both return a new socket; they never mutate in place.

```elixir
socket
|> Mob.Socket.assign(:loading, false)
|> Mob.Socket.assign(:items, items)
|> Mob.Socket.push_screen(MyApp.DetailScreen, %{id: id})
```

## Safe area

The socket always has a `:safe_area` assign populated by the framework:

```elixir
assigns.safe_area
#=> %{top: 62.0, right: 0.0, bottom: 34.0, left: 0.0}
```

Use it to avoid content being obscured by the notch, home indicator, or status bar:

```elixir
def render(assigns) do
  sa = assigns.safe_area
  %{
    type: :column,
    props: %{padding_top: sa.top, padding_bottom: sa.bottom},
    children: [...]
  }
end
```

## System back

The framework handles the system back gesture (Android hardware back / swipe, iOS edge-pan) automatically. If there is a screen behind the current one in the navigation stack, it pops. If the stack is empty, the app exits. You do not need to handle `{:mob, :back}` unless you want to override this behaviour.
