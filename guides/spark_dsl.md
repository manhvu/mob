# Spark DSL Guide

Dala provides a Spark DSL for defining screens declaratively. This guide explains how to use it.

## Overview

The Spark DSL allows you to define screens using a declarative syntax instead of writing render functions manually. It provides:

- **Attribute declarations** for screen state
- **UI component entities** for building the interface
- **@ref syntax** for referencing assign values in strings
- **Compile-time verification** for prop validation
- **Automatic mount function generation**

## Getting Started

To use the Spark DSL, add `use Dala.Spark.Dsl` to your screen module and wrap your declarations in a `dala do...end` block:

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl

  dala do
    attribute :count, :integer, default: 0

    screen name: :counter do
      text "Count: @count"
      button "Increment", on_tap: :increment
    end
  end

  def handle_event(:increment, _params, socket) do
    new_count = Dala.Socket.get_assign(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

## Attributes

Attributes define the screen's state. They are automatically initialized in the generated `mount/3` function.

### Syntax

```elixir
attribute :name, :type, default: value
```

### Supported Types

- `:integer`
- `:string`
- `:boolean`
- `:float`

### Example

```elixir
dala do
  attribute :count, :integer, default: 0
  attribute :message, :string, default: "Hello"
  attribute :visible, :boolean, default: true
end
```

## UI Components

Components are defined inside the `screen` block. Each component generates a node in the render tree.

### Text

```elixir
text "Hello, world!"
text "Count: @count", text_size: 18, text_color: :blue
```

### Button

```elixir
button "Press me", on_tap: :button_pressed
button "Submit", on_tap: :submit, background: :green, text_color: :white
```

### Image

```elixir
image "https://example.com/photo.jpg"
image "logo.png", width: 100, height: 100, resize_mode: :contain
```

### Switch

```elixir
switch value: true, on_toggle: :toggle_switch
```

### WebView

```elixir
webview "https://elixir-lang.org"
webview "https://example.com", show_url: true, width: 400, height: 600
```

### Other Components

- `camera_preview` - Live camera feed
- `native_view` - Platform-native component
- `activity_indicator` - Loading spinner
- `modal` - Modal overlay
- `scroll` - Scrollable container
- `safe_area` - Safe area view
- `status_bar` - Status bar control
- `progress_bar` - Progress bar
- `list` - Data-driven list
- `refresh_control` - Pull-to-refresh control
- `pressable` - Pressable wrapper

## @ref Syntax

The `@ref` syntax allows you to reference assign values in strings. It's processed at compile time and replaced with `assigns.key` access.

### Basic Usage

```elixir
text "Count: @count"  # Becomes: "Count: " <> assigns.count
```

### In Props

```elixir
button "@message", on_tap: :press  # Button text uses the @message assign
```

### Nested Structures

The `@ref` syntax is processed recursively in lists and maps:

```elixir
# This works - @count is replaced in the string
text ["Count: @count", " items"]

# This works - @message is replaced in the map value
some_component meta: %{label: "@message"}
```

## Compile-time Verification

The DSL includes verifiers that check your declarations at compile time:

- Validates that `on_tap` handlers are atoms
- Validates that attribute types are supported
- Provides helpful error messages for misconfigurations

## Generated Functions

The DSL transformers automatically generate:

### mount/3

Initializes all attributes with their default values:

```elixir
def mount(_params, _session, socket) do
  socket = Dala.Socket.assign(socket, :count, 0)
  socket = Dala.Socket.assign(socket, :message, "Hello")
  {:ok, socket}
end
```

### render/1

Builds the component tree from your DSL declarations:

```elixir
def render(assigns) do
  %{
    type: Dala.Spark.Dsl.Text,
    props: %{text: "Count: " <> assigns.count},
    children: []
  }
  # ... more components
end
```

## Event Handling

Event handlers are defined as regular `handle_event/3` functions. The `on_tap`, `on_toggle`, etc. props reference these handlers by atom name:

```elixir
def handle_event(:increment, _params, socket) do
  # Handle the event
  {:noreply, socket}
end
```

## Migration from Manual Screens

To migrate an existing screen to the Spark DSL:

1. Add `use Dala.Spark.Dsl` to your module
2. Move state declarations to `attribute` calls
3. Move render logic to the `screen` block
4. Remove the manual `mount/3` and `render/1` functions
5. Keep `handle_event/3` functions as-is

### Before

```elixir
defmodule MyApp.Counter do
  use Dala.Screen

  def mount(_params, _session, socket) do
    socket = Dala.Socket.assign(socket, :count, 0)
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Text text="Count: #{assigns.count}" />
    <Button text="Increment" on_tap={:increment} />
    """
  end

  def handle_event(:increment, _params, socket) do
    new_count = Dala.Socket.get_assign(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

### After

```elixir
defmodule MyApp.Counter do
  use Dala.Spark.Dsl

  dala do
    attribute :count, :integer, default: 0

    screen name: :counter do
      text "Count: @count"
      button "Increment", on_tap: :increment
    end
  end

  def handle_event(:increment, _params, socket) do
    new_count = Dala.Socket.get_assign(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

## Future Enhancements

Planned features for the Spark DSL:

- **Inline handlers**: Support `button do...end` blocks for inline event handling
- **Component composition**: Reusable component definitions within the DSL
- **Animation DSL**: Declarative animation definitions
- **Style DSL**: Reusable style definitions
