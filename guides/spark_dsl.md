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

To use the Spark DSL, add `use Dala.Spark.Dsl` (or `use Dala.Screen`) to your screen module:

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl

  attributes do
    attribute :count, :integer, default: 0
  end

  screen do
    name :counter
    column do
      gap :space_sm
      text "Count: @count"
      button "Increment", on_tap: :increment
    end
  end

  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
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
- `:atom`
- `:list`
- `:map`

### Example

```elixir
attributes do
  attribute :count, :integer, default: 0
  attribute :message, :string, default: "Hello"
  attribute :visible, :boolean, default: true
  attribute :items, :list, default: []
end
```

## Screen Section

The `screen` section holds all UI components. It requires a `name` option:

```elixir
screen do
  name :my_screen
  # components go here
end
```

## Layout Containers

Container components support nested children via `do...end` blocks. Props are set inside the block:

### Column (VStack)

```elixir
column do
  padding :space_md
  gap :space_sm
  text "Title"
  text "Subtitle"
end
```

### Row (HStack)

```elixir
row do
  gap :space_sm
  icon "settings"
  text "Settings"
end
```

### Box (ZStack)

Children overlap — useful for overlays:

```elixir
box do
  image "bg.jpg"
  text "Overlay", text_color: :white
end
```

### Scroll

```elixir
scroll do
  padding :space_md
  text "Long content..."
end
```

### Modal

```elixir
modal do
  visible true
  on_dismiss :dismissed
  text "Modal content"
end
```

### Pressable

```elixir
pressable do
  on_press :card_tapped
  text "Tap me"
end
```

### SafeArea

```elixir
safe_area do
  text "Safe content"
end
```

## Leaf Components

Leaf components have no children. They accept props as keyword arguments:

### Text

```elixir
text "Hello, world!"
text "Count: @count", text_size: :xl, text_color: :on_surface
text "Title", font_weight: "bold", text_align: :center
```

### Button

```elixir
button "Press me", on_tap: :button_pressed
button "Submit", on_tap: :submit, background: :primary, text_color: :on_primary
button "Disabled", on_tap: :action, disabled: true
```

### Icon

```elixir
icon "settings", text_size: 24, text_color: :on_surface
icon "chevron_right", on_tap: :navigate
```

### Image

```elixir
image "https://example.com/photo.jpg"
image "logo.png", width: 100, height: 100, resize_mode: :contain
```

### TextField

```elixir
text_field placeholder: "Enter name", on_change: :name_changed
text_field keyboard_type: :email, return_key: :next, on_submit: :next_field
```

### Toggle

```elixir
toggle value: true, on_change: :notifications_toggled, text: "Notifications"
```

### Slider

```elixir
slider value: 0.5, min_value: 0, max_value: 100, on_change: :volume_changed
```

### Switch (legacy)

```elixir
switch value: true, on_toggle: :toggled
```

### Video

```elixir
video "https://example.com/clip.mp4", autoplay: true, loop: true
```

### Other Leaf Components

- `divider()` — horizontal divider line
- `spacer()` — flexible space (or `spacer size: 20` for fixed)
- `activity_indicator size: :large, color: :primary` — loading spinner
- `progress_bar progress: 0.7, color: :primary` — progress bar
- `status_bar bar_style: :light_content` — status bar control
- `refresh_control on_refresh: :reload, refreshing: false` — pull-to-refresh
- `webview "https://elixir-lang.org"` — native web view
- `camera_preview facing: :front` — live camera feed
- `native_view MyComponent, id: :my_view` — platform-native component
- `tab_bar tabs: [%{id: "home", label: "Home"}]` — tab navigation
- `list :my_list, data: @items` — data-driven list

## @ref Syntax

The `@ref` syntax allows you to reference assign values in strings. It's processed at compile time and replaced with runtime assign access.

### Basic Usage

```elixir
text "Count: @count"  # Becomes: "Count: " <> to_string(assigns[:count])
```

### In Props

```elixir
button "@message", on_tap: :press  # Button text uses the @message assign
```

## Compile-time Verification

The DSL includes verifiers that check your declarations at compile time:

- Validates that all event handler props (`on_tap`, `on_change`, etc.) are atoms
- Validates that attribute types are supported
- Provides helpful error messages for misconfigurations

## Generated Functions

The DSL transformers automatically generate:

### mount/3

Initializes all attributes with their default values. Always generated, even without attributes:

```elixir
def mount(_params, _session, socket) do
  socket = Dala.Socket.assign(socket, :count, 0)
  {:ok, socket}
end
```

### render/1

Builds the component tree from your DSL declarations. Returns a list of top-level node maps:

```elixir
def render(assigns) do
  [
    %{
      type: :column,
      props: %{gap: :space_sm},
      children: [
        %{type: :text, props: %{text: "Count: " <> to_string(assigns[:count])}, children: []}
      ]
    }
  ]
end
```

## Event Handling

Event handlers are defined as regular `handle_event/3` functions. The `on_tap`, `on_change`, etc. props reference these handlers by atom name:

```elixir
def handle_event(:increment, _params, socket) do
  {:noreply, socket}
end
```

## Integration with Dala.App

Register Spark DSL screens in your app's `navigation/1` using `Dala.App.screens/1`:

```elixir
defmodule MyApp do
  use Dala.App

  def navigation(_) do
    screens([MyApp.HomeScreen, MyApp.CounterScreen, MyApp.SettingsScreen])
    stack(:home, root: MyApp.HomeScreen)
  end
end
```

## Migration from Manual Screens

To migrate an existing screen to the Spark DSL:

1. Add `use Dala.Spark.Dsl` (or keep `use Dala.Screen`) to your module
2. Move state declarations to `attributes do ... end`
3. Move render logic to the `screen do ... end` block
4. Remove the manual `mount/3` and `render/1` functions
5. Keep `handle_event/3` functions as-is

### Before

```elixir
defmodule MyApp.Counter do
  use Dala.Screen

  def mount(_params, _session, socket) do
    {:ok, Dala.Socket.assign(socket, :count, 0)}
  end

  def render(assigns) do
    Dala.UI.column([padding: :space_md, gap: :space_sm], [
      Dala.UI.text(text: "Count: #{assigns.count}"),
      Dala.UI.button(text: "Increment", on_tap: {self(), :increment})
    ])
  end

  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end
end
```

### After

```elixir
defmodule MyApp.Counter do
  use Dala.Spark.Dsl

  attributes do
    attribute :count, :integer, default: 0
  end

  screen do
    name :counter
    column do
      padding :space_md
      gap :space_sm
      text "Count: @count"
      button "Increment", on_tap: :increment
    end
  end

  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end
end
```
