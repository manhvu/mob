# Testing

Dala supports two levels of testing: unit tests for screen logic (no device required) and live inspection of a running app via Erlang distribution.

## Unit testing screens

`Dala.Screen.start_link/2` starts a screen process in `:no_render` mode — it runs all Elixir callbacks but skips NIF calls. Use it in `ExUnit` tests:

```elixir
defmodule MyApp.CounterScreenTest do
  use ExUnit.Case

  test "increments count on tap" do
    {:ok, pid} = Dala.Screen.start_link(MyApp.CounterScreen, %{})

    # Read initial state
    socket = Dala.Screen.get_socket(pid)
    assert socket.assigns.count == 0

    # Dispatch an event
    :ok = Dala.Screen.dispatch(pid, "tap", %{"tag" => "increment"})

    # Verify updated state
    socket = Dala.Screen.get_socket(pid)
    assert socket.assigns.count == 1
  end

  test "navigates to detail on tap" do
    {:ok, pid} = Dala.Screen.start_link(MyApp.HomeScreen, %{})
    :ok = Dala.Screen.dispatch(pid, "tap", %{"tag" => "open_detail"})

    assert Dala.Screen.get_current_module(pid) == MyApp.DetailScreen
  end
end
```

Key functions for test-mode screens:
- `Dala.Screen.get_socket/1` — returns the current `Dala.Socket.t()`
- `Dala.Screen.dispatch/3` — sends an event, blocks until processed
- `Dala.Screen.get_current_module/1` — returns the current screen module (after navigation)
- `Dala.Screen.get_nav_history/1` — returns the navigation stack as `[{module, socket}]`

`get_current_module/1` and `get_nav_history/1` are also available via `Dala.Test` on live nodes:

```elixir
Dala.Test.screen(node)         #=> current module (alias for get_current_module)
Dala.Test.get_nav_history(node) #=> full navigation stack
```

## Testing handle_info

Send messages directly to the screen process:

```elixir
test "handles location update" do
  {:ok, pid} = Dala.Screen.start_link(MyApp.MapScreen, %{})

  send(pid, {:location, %{lat: 43.6532, lon: -79.3832, accuracy: 10.0, altitude: 80.0}})
  # handle_info is async — wait for the message to process
  :sys.get_state(pid)  # sync point: blocks until GenServer is idle

  socket = Dala.Screen.get_socket(pid)
  assert socket.assigns.location.lat == 43.6532
end
```

## Live inspection with Dala.Test

After `mix dala.connect`, `Dala.Test` gives you a remote view into the running app.

### Inspection

```elixir
node = :"my_app_ios@127.0.0.1"

# Current screen module
Dala.Test.screen(node)    #=> MyApp.HomeScreen

# Live socket assigns
Dala.Test.assigns(node)   #=> %{count: 3, safe_area: %{top: 62.0, ...}}

# Full widget tree
Dala.Test.tree(node)      #=> %{type: :column, props: %{...}, children: [...]}

# Find widget by visible text
Dala.Test.find(node, "Increment")
#=> [{[0, 1], %{"type" => "button", "props" => %{"text" => "Increment", ...}}}]}

# Full snapshot (screen + assigns + nav stack + widget tree)
Dala.Test.inspect(node)
#=> %{
#=>   screen: MyApp.HomeScreen,
#=>   assigns: %{count: 3, ...},
#=>   nav_history: [{MyApp.HomeScreen, %{...}}, {MyApp.DetailScreen, %{...}}],
#=>   tree: %{type: :column, ...}
#=> }
```

`Dala.Test.inspect/1` is the fastest way to get full state — one RPC instead of four.

### Taps

```elixir
Dala.Test.tap(node, :increment)
```

The tag atom comes from `on_tap: {self(), :increment}` in the screen's `render/1`. Fire-and-forget — does not block.

### Navigation

Navigation functions are **synchronous** — they block until the navigation and re-render are complete, so it is safe to read state immediately after:

```elixir
Dala.Test.pop(node)                               # pop to previous screen
Dala.Test.navigate(node, MyApp.DetailScreen, %{id: 42})
Dala.Test.navigate(node, :detail, %{id: 42})      # by registered name
Dala.Test.pop_to(node, MyApp.HomeScreen)          # pop back to a specific screen
Dala.Test.pop_to_root(node)                       # pop all the way back
Dala.Test.reset_to(node, MyApp.HomeScreen)        # replace the entire stack

# System back gesture (fire-and-forget — same as hardware back / edge-pan)
Dala.Test.back(node)
```

### List interaction

```elixir
Dala.Test.select(node, :my_list, 0)   # select first row
```

The list ID comes from the `:id` prop on the `type: :list` node. Delivers `{:select, :my_list, 0}` to `handle_info/2`.

### Simulating device API results

Use `send_message/2` to deliver any term to `handle_info/2` — useful for simulating async device results without triggering real hardware:

```elixir
# Permissions
Dala.Test.send_message(node, {:permission, :camera, :granted})
Dala.Test.send_message(node, {:permission, :notifications, :denied})

# Camera / Photos / Files
Dala.Test.send_message(node, {:camera, :photo, %{path: "/tmp/photo.jpg", width: 1920, height: 1080}})
Dala.Test.send_message(node, {:camera, :cancelled})
Dala.Test.send_message(node, {:photos, :picked, [%{path: "/tmp/photo.jpg", width: 800, height: 600}]})
Dala.Test.send_message(node, {:files, :picked, [%{path: "/tmp/doc.pdf", name: "doc.pdf", size: 4096}]})

# Location / Motion
Dala.Test.send_message(node, {:location, %{lat: 43.6532, lon: -79.3832, accuracy: 10.0, altitude: 80.0}})
Dala.Test.send_message(node, {:motion, %{ax: 0.1, ay: 9.8, az: 0.0, gx: 0.0, gy: 0.0, gz: 0.0}})

# Notifications / Push
Dala.Test.send_message(node, {:notification, %{id: "n1", title: "Hi", body: "Hello", data: %{}, source: :push}})
Dala.Test.send_message(node, {:push_token, :ios, "abc123"})

# Biometric / Scanner
Dala.Test.send_message(node, {:biometric, :success})
Dala.Test.send_message(node, {:scan, :result, %{type: :qr, value: "https://example.com"}})

# Audio recording
Dala.Test.send_message(node, {:audio, :recorded, %{path: "/tmp/rec.aac", duration: 3.2}})
Dala.Test.send_message(node, {:audio, :error, :permission_denied})

# Audio playback
Dala.Test.send_message(node, {:audio, :playback_finished, %{path: "/tmp/clip.m4a"}})
Dala.Test.send_message(node, {:audio, :playback_error, %{reason: :file_not_found}})

# WebView
Dala.Test.send_message(node, {:webview, :message, %{"event" => "clicked", "id" => 42}})
Dala.Test.send_message(node, {:webview, :blocked, "https://blocked.example.com"})
Dala.Test.send_message(node, {:webview, :eval_result, "Page Title"})

# Alert / action sheet
Dala.Test.send_message(node, {:alert, :confirmed_delete})
Dala.Test.send_message(node, {:alert, :dismiss})

# Custom
Dala.Test.send_message(node, {:my_event, %{key: "value"}})
```

`send_message/2` is fire-and-forget. Use `:sys.get_state` as a sync point if you need to wait before reading state. Pass the screen pid retrieved via `Dala.Test`:

```elixir
Dala.Test.send_message(node, {:permission, :camera, :granted})
pid = Dala.Test.screen_pid(node)
:rpc.call(node, :sys, :get_state, [pid])  # blocks until the GenServer is idle
Dala.Test.assigns(node)
```

### Native UI interaction

`Dala.Test.tap_native/1` locates an element via the iOS accessibility tree and sends a real touch event. **iOS only.** Requires `idb` — install it with `brew install facebook/fb/idb-companion`.

```elixir
Dala.Test.tap_native("Increment")   # by visible text
Dala.Test.tap_native(:increment)    # by accessibility_id (= tag atom name)

Dala.Test.locate("Increment")
#=> {:ok, %{x: 0.0, y: 412.0, width: 402.0, height: 44.0}}
```

Use `tap_native/1` when you need to test the native gesture path end-to-end. Prefer `tap/2` for testing Elixir logic — it's faster, works on both platforms, and doesn't require `idb`.

## Hot code push in development

During development, push a single module without restarting:

```bash
# After editing MyApp.SomeScreen:
mix compile && nl(MyApp.SomeScreen)
#=> {:ok, [{:"my_app_ios@127.0.0.1", :loaded, MyApp.SomeScreen}]}
```

`nl/1` is a built-in IEx helper that loads new bytecode on all connected nodes. The running screen process picks up the new code on the next `handle_*` call.

## Integration test patterns

For tests that require a running app, use `@tag :integration` and exclude them in CI:

```elixir
@tag :integration
test "app shows home screen after launch" do
  node = :"my_app_ios@127.0.0.1"
  assert Dala.Test.screen(node) == MyApp.HomeScreen
end
```

Run only unit tests (skipping integration):

```bash
mix test --exclude integration
```

Run only integration tests:

```bash
mix test --only integration
```
