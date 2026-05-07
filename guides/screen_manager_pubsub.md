# Screen Manager & PubSub

Dala provides two powerful features for inter-screen communication and screen lifecycle management:

1. **Screen Manager** - Auto-registers screens with unique IDs, allows querying by name/id/pid
2. **PubSub** - Lightweight publish-subscribe for broadcasting messages between screens

## Screen Manager

The `Dala.Screen.Manager` tracks all active screens in your application. Screens auto-register when started and unregister when they terminate.

### Features

- **Auto-registration**: Screens register themselves automatically on start
- **Unique IDs**: Each screen gets a sequential integer ID
- **Multiple lookup methods**: Find screens by ID, name, or PID
- **List all screens**: Get a snapshot of all active screens

### API

#### `Dala.Screen.Manager`

```elixir
# Register a screen (called automatically by Dala.Screen)
Dala.Screen.Manager.register(id, name, pid, module)

# Unregister a screen (called automatically on terminate)
Dala.Screen.Manager.unregister(pid)

# Generate a unique screen ID
Dala.Screen.Manager.next_id()

# List all registered screens
Dala.Screen.Manager.list()
# => [%{id: 0, name: :home, pid: #PID<0.123.0>, module: MyApp.HomeScreen}]

# Send a message to a screen by identifier
Dala.Screen.Manager.dispatch(:home, {:update, data})
Dala.Screen.Manager.dispatch(0, {:update, data})
Dala.Screen.Manager.dispatch(pid, {:update, data})
```

#### `Dala.Screen`

```elixir
# Send a message to any screen
Dala.Screen.dispatch(:home, {:update, data})
Dala.Screen.dispatch(0, {:update, data})
Dala.Screen.dispatch(pid, {:update, data})

# List all screens
Dala.Screen.list()
# => [%{id: 0, name: :home, pid: #PID<0.123.0>, module: MyApp.HomeScreen}]
```

### Usage Example

```elixir
defmodule MyApp.HomeScreen do
  use Dala.Screen

  screen do
    name :home
    column do
      text "Home Screen"
    end
  end

  def handle_info({:update, data}, socket) do
    # Handle messages from other screens
    {:noreply, Dala.Socket.assign(socket, :data, data)}
  end
end

# From another module or screen
defmodule MyApp.OtherScreen do
  use Dala.Screen

  def handle_event(:send_update, _params, socket) do
    # Send message to home screen by name
    Dala.Screen.dispatch(:home, {:update, %{value: 42}})
    {:noreply, socket}
  end
end
```

## PubSub

`Dala.PubSub` provides a lightweight publish-subscribe system using Elixir's built-in `Registry`. No Redis, no adapters — just fast local pubsub.

### Features

- **Simple API**: Subscribe, unsubscribe, broadcast
- **Local-only**: Fast in-process communication
- **No dependencies**: Uses Elixir's Registry
- **Broadcast exclusion**: `broadcast_from/4` excludes the sender

### API

```elixir
# Start a pubsub instance (in your supervision tree)
{Dala.PubSub, name: MyApp.PubSub}

# Subscribe to a topic
Dala.PubSub.subscribe(MyApp.PubSub, "user:123")

# Unsubscribe from a topic
Dala.PubSub.unsubscribe(MyApp.PubSub, "user:123")

# Broadcast to all subscribers
Dala.PubSub.broadcast(MyApp.PubSub, "user:123", {:message, data})

# Broadcast excluding the sender
Dala.PubSub.broadcast_from(MyApp.PubSub, self(), "user:123", {:message, data})

# Get subscriber count
Dala.PubSub.subscriber_count(MyApp.PubSub, "user:123")
```

### Usage Example

```elixir
defmodule MyApp do
  use Application

  def start(_type, _args) do
    children = [
      {Dala.PubSub, name: MyApp.PubSub}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

defmodule MyApp.ChatScreen do
  use Dala.Screen

  screen do
    name :chat
    column do
      text "Chat Room"
    end
  end

  def mount(_params, _session, socket) do
    # Subscribe to chat room on mount
    Dala.PubSub.subscribe(MyApp.PubSub, "chat:room:123")
    {:ok, socket}
  end

  def handle_info({:message, text}, socket) do
    # Handle incoming messages
    messages = socket.assigns.messages ++ [text]
    {:noreply, Dala.Socket.assign(socket, :messages, messages)}
  end

  def handle_event(:send_message, %{"text" => text}, socket) do
    # Broadcast message to all subscribers
    Dala.PubSub.broadcast(MyApp.PubSub, "chat:room:123", {:message, text})
    {:noreply, socket}
  end
end
```

### Spark DSL Integration

You can also declare PubSub subscriptions declaratively in your screens:

```elixir
defmodule MyApp.ChatScreen do
  use Dala.Spark.Dsl

  dala do
    attribute :messages, :list, default: []

    pubsub do
      subscribe "chat:room:123", on_message: :handle_chat
    end

    screen name: :chat do
      column do
        text "Messages: @messages"
      end
    end
  end

  def handle_chat({:message, text}, socket) do
    messages = socket.assigns.messages ++ [text]
    {:noreply, Dala.Socket.assign(socket, :messages, messages)}
  end
end
```

## Comparison with Phoenix.PubSub

| Feature | Phoenix.PubSub | Dala.PubSub |
|---------|---------------|-------------|
| Adapters | PG2, Redis | None (Registry only) |
| Distribution | Yes (multi-node) | No (local only) |
| Dependencies | phoenix_pubsub | None |
| API | Full-featured | Minimal |
| Use case | Multi-server apps | Single-device apps |

Dala.PubSub is designed for single-device applications where you need fast, simple pubsub without the overhead of distributed systems. For multi-node scenarios, use Phoenix.PubSub with the PG2 or Redis adapter.
