# UI Design Guide

This guide explains how to design UI components in Dala using the Spark DSL.

The DSL style uses `Dala.Spark.Dsl` to define screens declaratively with automatic boilerplate generation.

## Quick Comparison

| Aspect | DSL Style |
|--------|----------|
| Syntax | `dala do...end` block |
| Learning curve | Declarative, less Elixir boilerplate |
| State management | `attribute` declarations, auto-generated `mount/3` |
| Render function | Auto-generated from `screen` block |
| @ref syntax | `@count` expands to `assigns.count` |
| Compile-time checks | Attribute types, handler verification |
| Best for | Standard screens, rapid prototyping |

## DSL Style (Spark DSL)

The DSL style uses `Dala.Spark.Dsl` to define screens declaratively with automatic boilerplate generation.

### Basic Structure

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl

  dala do
    attribute :count, :integer, default: 0

    screen name: :counter do
      text "Count: @count", text_size: :xl
      spacer size: 16
      button "Increment", on_tap: :increment
    end
  end

  def handle_event(:increment, _params, socket) do
    new_count = Dala.Socket.get(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

### Key Points

- **Attributes**: Declare state with `attribute :name, :type, default: value`
- **@ref syntax**: Use `@count` in strings to reference assigns (expanded at compile time)
- **Auto-generation**: `mount/3` and `render/1` are generated automatically
- **Handlers**: Reference as atoms (`:increment`) instead of `{self(), :tag}` tuples
- **Events**: Use `handle_event/3` instead of `handle_info/2` for component events

## Component Design Patterns

### Shared Components

Use helper functions within the DSL:

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl

  dala do
    attribute :count, :integer, default: 0

    screen name: :counter do
      text "Count: @count"
      my_button "Increment", on_tap: :increment
    end
  end

  # Helper function for DSL
  def my_button(label, opts) do
    button label, Keyword.merge([background: :primary, text_color: :on_primary], opts)
  end

  def handle_event(:increment, _params, socket) do
    new_count = Dala.Socket.get(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

### Conditional Rendering

```elixir
dala do
  attribute :show_details, :boolean, default: false

  screen do
    text "Always visible"
    if @show_details do
      text "Details here"
    else
      text "Hidden"
    end
  end
end
```

### Lists and Iteration

```elixir
dala do
  attribute :items, :list, default: []

  screen do
    column do
      {Enum.map(@items, fn item ->
        text item, padding: :space_sm
      end)}
    end
  end
end
```

## Event Handling

In DSL style, event handlers are atoms that map directly to `handle_event/3` clauses:

```elixir
dala do
  screen do
    button "Save", on_tap: :save
  end
end

def handle_event(:save, _params, socket) do
  # Handle save
  {:noreply, socket}
end
```

## Styling and Theming

`Dala.Style` works for reusable styles:

```elixir
@card_style %Dala.Style{props: %{background: :surface, padding: :space_md}}

dala do
  screen do
    box style: @card_style do
      text "Hello"
    end
  end
end
```

## Best Practices

- Use descriptive attribute names
- Leverage `@ref` syntax for cleaner templates
- Keep `handle_event/3` functions focused
- Use the `screen` block for static layouts, expression slots for dynamic content

For shared utilities, `Dala.Ui.Widgets` functions return plain maps that work with the DSL:

```elixir
# Works in both sigil and DSL screens
Dala.Ui.Widgets.text(text: "Hello")
```

## Further Reading

- [Components](components.md) — DSL component reference
- [Spark DSL](spark_dsl.md) — In-depth DSL documentation
- [Theming](theming.md) — Colors, spacing, and typography tokens
- [Events](events.md) — Event system and message passing