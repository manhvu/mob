# Screen Lifecycle

A Dala screen is a GenServer wrapped by `Dala.Screen`. Each screen in the navigation stack is a separate, supervised process. Understanding the lifecycle means understanding when each callback fires and what you can do in it.

## Callbacks

### `mount/3`

```elixir
@callback mount(params :: map(), session :: map(), socket :: Dala.Ui.Socket.t()) ::
  {:ok, Dala.Ui.Socket.t()} | {:error, term()}
```

Called once when the screen process starts. Initialize your assigns here.

`params` comes from the navigation call that opened this screen:

```elixir
# Screen A navigates to Screen B with params:
Dala.Ui.Socket.push_screen(socket, MyApp.DetailScreen, %{id: 42})

# Screen B receives them in mount:
def mount(%{id: id}, _session, socket) do
  item = fetch_item(id)
  {:ok, Dala.Ui.Socket.assign(socket, :item, item)}
end
```

`session` is reserved for future use; pass it through.

If `mount/3` returns `{:error, reason}`, the GenServer stops with that reason.

### `render/1`

```elixir
@callback render(assigns :: map()) :: map()
```

Returns the component tree as a plain Elixir map. Called after every callback that returns a modified socket. The renderer serialises the tree, resolves tokens, and calls the NIF — Compose or SwiftUI diffs and updates the display.

In DSL style, the `screen` block compiles to the same maps at compile time:

```elixir
dala do
  screen name: :home do
    column padding: :space_md, background: :background do
      text "@title", text_size: :xl, text_color: :on_background
      button "Save", on_tap: :save
    end
  end
end
```

Keep `render/1` pure. No side effects, no process sends. It may be called more than once for a given state.

### `handle_info/2`

```elixir
@callback handle_info(message :: term(), socket :: Dala.Ui.Socket.t()) ::
  {:noreply, Dala.Ui.Socket.t()}
```

The primary callback for responding to user interaction and async results. All UI events — taps, text changes, list selections — arrive here as messages sent by the NIF directly to the screen process.

**Tap events** are delivered as atoms matching the `on_tap` handler you specified in the `screen` block:

```elixir
# In the screen block:
button "Save", on_tap: :save

# In handle_event:
def handle_event(:save, _params, socket) do
  save_data(socket.assigns)
  {:noreply, socket}
end
```

**Text field changes** arrive as `{:change, tag, value}`:

```elixir
# In the screen block:
text_field text: @name, on_change: :name_changed

# In handle_event:
def handle_event({:change, :name_changed, value}, _params, socket) do
  {:noreply, Dala.Ui.Socket.assign(socket, :name, value)}
end
```

**Device API results** also arrive here — see [Device Capabilities](device_capabilities.md):

```elixir
def handle_info({:camera, :photo, %{path: path}}, socket) do
  {:noreply, Dala.Ui.Socket.assign(socket, :photo_path, path)}
end

def handle_info({:camera, :cancelled}, socket) do
  {:noreply, socket}
end
```

Navigation is triggered by returning a modified socket:

```elixir
def handle_event(:open_detail, _params, socket) do
  {:noreply, Dala.Ui.Socket.push_screen(socket, MyApp.DetailScreen, %{id: socket.assigns.id})}
end
```

The default implementation (from `use Dala.Spark.Dsl`) is a no-op that returns the socket unchanged.

### `handle_event/3`

```elixir
@callback handle_event(event :: term(), params :: map(), socket :: Dala.Ui.Socket.t()) ::
  {:noreply, Dala.Ui.Socket.t()} | {:reply, map(), Dala.Ui.Socket.t()}
```

The primary callback for responding to user interaction in DSL-style screens. All UI events — taps, text changes, list selections — arrive here.

```elixir
# Tap event:
def handle_event(:save, _params, socket) do
  save_data(socket.assigns)
  {:noreply, socket}
end

# Change event with value:
def handle_event({:change, :name_changed, value}, _params, socket) do
  {:noreply, Dala.Ui.Socket.assign(socket, :name, value)}
end
```

Can also be dispatched programmatically via `Dala.Screen.Screen.dispatch/3` for tests:

```elixir
Dala.Screen.Screen.dispatch(pid, :increment, %{})
```

### `terminate/2`

```elixir
@callback terminate(reason :: term(), socket :: Dala.Ui.Socket.t()) :: term()
```

Called when the screen process is about to stop. Use it for cleanup — cancel timers, release resources. The return value is ignored.

The default is a no-op. Most screens don't need to implement this.

## Starting screens

### `Dala.Screen.Screen.start_root/3`

Called by `Dala.App` to start the root screen of the navigation stack. This is the entry point for your app's UI. If it returns `{:error, reason}`, the app crashes loudly (see AGENTS.md rule #2).

```elixir
{:ok, pid} = Dala.Screen.Screen.start_root(MyApp.HomeScreen, %{}, nil)
```

`Dala.Screen.start_link/3` is for testing — it starts the screen in `:no_render` mode, skipping NIF calls but running all Elixir callbacks:

```elixir
{:ok, pid} = Dala.Screen.start_link(MyApp.CounterScreen, %{})
```

## Event handling: handle_event vs handle_info

### `handle_event/3` — Primary callback for DSL screens

All UI events (taps, text changes, list selections) arrive here. This is the main event callback for DSL-style screens.

```elixir
def handle_event(:save, _params, socket) do
  save_data(socket.assigns)
  {:noreply, socket}
end
```

### `handle_info/2` — Device API results and raw messages

Device API results (camera, location, etc.) and other raw messages still arrive via `handle_info/2`:

```elixir
def handle_info({:camera, :photo, %{path: path}}, socket) do
  {:noreply, Dala.Ui.Socket.assign(socket, :photo_path, path)}
end
```

**Rule of thumb:** Use `handle_event/3` for UI events. Use `handle_info/2` for device API results and raw process messages.

## Lifecycle flow

```
start_root/3 or start_link/3
        │
        ▼
   mount/3  ──────────────────────────────────────────────┐
        │                                                  │
        ▼                                                  │
   render/1  ─ NIF set_root / set_view                    │
        │                                                  │
        ├── user taps button ────► handle_event/3  ──► render/1
        │                                                  │
        ├── text field change ───► handle_event/3  ──► render/1
        │                                                  │
        ├── device API result ───► handle_info/2  ──► render/1
        │                                                  │
        ├── send(pid, msg)  ──────► handle_info/2  ──► render/1
        │                                                  │
        └── screen popped from stack ─► terminate/2  ──────┘
```

## terminate/2 — Cleanup callback

Called when the screen process stops (popped from stack, app exit, or error). Use for resource cleanup:

```elixir
def terminate(_reason, socket) do
  # Stop camera preview, cancel timers, release resources
  if preview = socket.assigns[:camera_preview] do
    Dala.Native.stop_camera_preview(preview)
  end
  :ok
end
```

The default is a no-op. Most screens don't need it.

## The socket

All callbacks receive and return a `Dala.Ui.Socket.t()`. Think of it as a struct carrying your screen's state:

- `socket.assigns` — your data (`:count`, `:user`, `:items`, etc.)
- `socket.__dala__` — internal framework state; do not touch directly

Use `Dala.Ui.Socket.assign/2,3` to update assigns. Use the navigation functions (`push_screen`, `pop_screen`, etc.) to queue navigation actions. Both return a new socket; they never mutate in place.

```elixir
socket
|> Dala.Ui.Socket.assign(:loading, false)
|> Dala.Ui.Socket.assign(:items, items)
|> Dala.Ui.Socket.push_screen(MyApp.DetailScreen, %{id: id})
```

## Safe area

The socket always has a `:safe_area` assign populated by the framework:

```elixir
assigns.safe_area
#=> %{top: 62.0, right: 0.0, bottom: 34.0, left: 0.0}
```

Use it to avoid content being obscured by the notch, home indicator, or status bar:

```elixir
dala do
  screen name: :home do
    column padding_top: @safe_area.top, padding_bottom: @safe_area.bottom do
      text "Content"
    end
  end
end
```

## System back

The framework handles the system back gesture (Android hardware back / swipe, iOS edge-pan) automatically. If there is a screen behind the current one in the navigation stack, it pops. If the stack is empty, the app exits. You do not need to handle `{:dala, :back}` unless you want to override this behaviour.