# Implementation Summary: Screen Manager & PubSub

## Overview

This implementation adds two powerful features to Dala for inter-screen communication and screen lifecycle management:

1. **Screen Manager** - Auto-registers screens with unique IDs, allows querying by name/id/pid
2. **PubSub** - Lightweight publish-subscribe for broadcasting messages between screens

## Files Created

### 1. `lib/dala/pubsub.ex`
- Core PubSub module using Elixir's Registry
- No Redis, no adapters — just fast local pubsub
- API: `subscribe/2`, `unsubscribe/2`, `broadcast/3`, `broadcast_from/4`, `subscriber_count/2`, `topics/1`

### 2. `lib/dala/screen/manager.ex`
- Central registry for tracking all active screens
- Auto-registration on screen start, auto-unregistration on terminate
- Unique ID generation using ETS counter
- API: `register/4`, `unregister/1`, `dispatch/2`, `list/0`, `next_id/0`

### 3. `lib/dala/spark/pubsub.ex`
- Spark DSL extension for declarative PubSub subscriptions
- Allows screens to declare subscriptions in the DSL
- Integrates with `Dala.Spark.Dsl`

### 4. `lib/dala/spark/transformers/pubsub.ex`
- Transformer that generates `handle_info/2` clauses for pubsub subscriptions
- Forwards messages to specified handler functions

### 5. `test/dala/pubsub_test.exs`
- Comprehensive tests for PubSub functionality
- 7 tests covering all API functions

### 6. `test/dala/screen/manager_test.exs`
- Comprehensive tests for Screen Manager functionality
- 13 tests covering registration, unregistration, dispatch, and integration

### 7. `guides/screen_manager_pubsub.md`
- Complete documentation for both features
- Usage examples, API reference, and comparison with Phoenix.PubSub

## Files Modified

### 1. `lib/dala/screen.ex`
- Added registration to `init/1`: generates ID, registers with manager
- Added unregistration to `terminate/2`: unregisters on screen stop
- Added 5-element state tuple support for `screen_id`:
  - `handle_call/3` (all variants)
  - `handle_info/2` (all variants)
  - `terminate/2` (all variants)
- Added `dispatch/2` convenience function
- Added `list/0` convenience function
- Updated to accept screen manager in `Dala.App` startup

### 2. `lib/dala/app.ex`
- Added `ensure_started(Dala.Screen.Manager)` to startup sequence

### 3. `lib/dala/spark/dsl.ex`
- Added `use Dala.Spark.PubSub` to enable pubsub DSL
- Added `Dala.Spark.Transformers.PubSub` to transformer pipeline

### 4. `mix.exs`
- Updated Erlang requirement to `>= 27.0` (for `persistent_term` support)

## Key Design Decisions

### Screen Manager
- Uses ETS for fast in-memory storage
- Auto-generates sequential IDs starting from 0
- Supports lookup by ID (integer), name (atom), or PID
- Screens register with their name from `socket.assigns[:name]`
- Gracefully handles missing ETS tables (for test environments)

### PubSub
- Uses Elixir's built-in `Registry` with `:duplicate` keys
- No external dependencies (no Redis, no PG2)
- Designed for single-device, local-only communication
- `broadcast_from/4` excludes sender to prevent echo
- Simple, minimal API focused on common use cases

### Spark DSL Integration
- Declarative subscriptions in screen DSL
- Automatic message forwarding to handler functions
- Type-safe schema validation
- Consistent with existing Spark patterns

## Testing

All tests pass:
- 7 PubSub tests
- 13 Screen Manager tests
- 302 existing Dala tests (no regressions)
- Total: 322 tests passing

## Usage Examples

### Screen Manager

```elixir
# Send message to screen by name
Dala.Screen.dispatch(:home, {:update, data})

# Send message to screen by ID
Dala.Screen.dispatch(0, {:update, data})

# Send message to screen by PID
Dala.Screen.dispatch(pid, {:update, data})

# List all screens
Dala.Screen.list()
# => [%{id: 0, name: :home, pid: #PID<0.123.0>, module: MyApp.HomeScreen}]
```

### PubSub

```elixir
# In your application
children = [
  {Dala.PubSub, name: MyApp.PubSub}
]

# In a screen
def mount(_params, _session, socket) do
  Dala.PubSub.subscribe(MyApp.PubSub, "chat:room:123")
  {:ok, socket}
end

def handle_info({:message, text}, socket) do
  # Handle incoming message
  {:noreply, socket}
end

def handle_event(:send, _params, socket) do
  Dala.PubSub.broadcast(MyApp.PubSub, "chat:room:123", {:message, "Hello"})
  {:noreply, socket}
end
```

### Spark DSL

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

## Benefits

1. **Simple inter-screen communication**: No complex event buses or state management
2. **Type-safe**: Compile-time validation of DSL schemas
3. **Lightweight**: No external dependencies, minimal overhead
4. **Consistent**: Follows Dala's existing patterns and conventions
5. **Well-tested**: Comprehensive test coverage
6. **Documented**: Complete guides and examples

## Future Enhancements

Potential future improvements:
- Screen groups/channels for broadcasting to multiple screens
- Message persistence for offline scenarios
- Priority queues for critical messages
- Message filtering/pattern matching
- Integration with Dala's event system
- Screen lifecycle hooks (on_mount, on_unmount)
