# UI Design Guide

This guide explains how to design UI components in Dala using two approaches:
- **Sigil Style** — Phoenix-style `~dala` sigil (imported automatically with `use Dala.Screen`)
- **DSL Style** — Declarative `Dala.Spark.Dsl` (Spark-based DSL)

Both styles produce identical output and are accepted by `Dala.Renderer`. Choose the style that fits your workflow.

## Quick Comparison

| Aspect | Sigil Style | DSL Style |
|--------|-------------|-----------|
| Syntax | `~dala"""..."""` | `dala do...end` block |
| Learning curve | Familiar to Phoenix/LiveView devs | More declarative, less Elixir boilerplate |
| State management | Manual `mount/3` + `assigns` | `attribute` declarations, auto-generated `mount/3` |
| Render function | Manual `render/1` | Auto-generated from `screen` block |
| @ref syntax | Not available | `@count` expands to `assigns.count` |
| Compile-time checks | Tag whitelist validation | Attribute types, handler verification |
| Best for | Complex rendering logic, dynamic UIs | Standard screens, rapid prototyping |

## Sigil Style (Phoenix-style)

The sigil style uses the `~dala` sigil to write declarative UI templates that compile to plain Elixir maps at compile time.

### Basic Structure

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Screen

  def mount(_params, _session, socket) do
    socket = Dala.Socket.assign(socket, :count, 0)
    {:ok, socket}
  end

  def render(assigns) do
    increment_tap = {self(), :increment}
    
    ~dala"""
    <Column padding={:space_md}>
      <Text text={"Count: #{assigns.count}"} text_size={:xl} />
      <Spacer size={16} />
      <Button text="Increment" on_tap={increment_tap} />
    </Column>
    """
  end

  def handle_info({:tap, :increment}, socket) do
    new_count = Dala.Socket.get_assign(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

### Key Points

- **Import**: `use Dala.Screen` automatically imports `Dala.Sigil`
- **Handler tuples**: Pre-compute `{self(), :tag}` tuples before the sigil
- **Expressions**: Use `{...}` for Elixir expressions in attributes or children
- **Assigns**: Access via `assigns.key` or `Dala.Socket.get_assign(socket, :key)`

### Expression Slots

```elixir
~dala"""
<Column>
  {Enum.map(assigns.items, fn item ->
    ~dala(<Text text={item} padding={:space_sm} />)
  end)}
</Column>
"""
```

### When to Use Sigil Style

- You're comfortable with Phoenix/LiveView syntax
- You need complex rendering logic with conditionals or loops
- You want full control over `mount/3` and `render/1`
- You're migrating from Phoenix LiveView

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
    new_count = Dala.Socket.get_assign(socket, :count) + 1
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

### @ref Syntax

The `@ref` syntax is processed at compile time and replaced with `assigns.key` access:

```elixir
dala do
  attribute :message, :string, default: "Hello"
  
  screen do
    text "@message"           # Becomes: "Hello"
    text "Value: @count"      # Becomes: "Value: " <> assigns.count
  end
end
```

### When to Use DSL Style

- You want less boilerplate (no manual `mount/3` or `render/1`)
- You're building standard screens with declarative UI
- You want compile-time verification of attributes and handlers
- You prefer a more concise, DSL-driven approach
- You're rapidly prototyping

## Component Design Patterns

### Shared Components with Sigil Style

Create reusable functions that return node maps:

```elixir
defmodule MyApp.Components do
  import Dala.Sigil

  def card(title, content) do
    ~dala"""
    <Box background={:surface} padding={:space_md} corner_radius={:radius_md}>
      <Text text={title} text_size={:lg} font_weight="bold" />
      <Spacer size={8} />
      <Text text={content} text_color={:muted} />
    </Box>
    """
  end
end

# Usage in screen:
def render(assigns) do
  ~dala"""
  <Column>
    {MyApp.Components.card("Welcome", "Hello there!")}
  </Column>
  """
end
```

### Shared Components with DSL Style

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
    new_count = Dala.Socket.get_assign(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

### Conditional Rendering

**Sigil Style:**

```elixir
def render(assigns) do
  ~dala"""
  <Column>
    <Text text="Always visible" />
    {if assigns.show_details do
      ~dala(<Text text="Details here" />)
    else
      ~dala(<Text text="Hidden" />)
    end}
  </Column>
  """
end
```

**DSL Style:**

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

**Sigil Style:**

```elixir
def render(assigns) do
  ~dala"""
  <Column>
    {Enum.map(assigns.items, fn item ->
      ~dala(<Text text={item} padding={:space_sm} />)
    end)}
  </Column>
  """
end
```

**DSL Style:**

```elixir
dala do
  attribute :items, :list, default: []

  screen do
    # Use expression child slot
    {Enum.map(@items, fn item ->
      text item, padding: :space_sm
    end)}
  end
end
```

## Event Handling

### Sigil Style Events

Uses `handle_info/2` with tagged tuples:

```elixir
def render(assigns) do
  save_tap = {self(), :save}
  ~dala(<Button text="Save" on_tap={save_tap} />)
end

def handle_info({:tap, :save}, socket) do
  # Handle save
  {:noreply, socket}
end
```

### DSL Style Events

Uses `handle_event/3` with atom references:

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

Both styles support `Dala.Style` for reusable styles:

```elixir
@card_style %Dala.Style{props: %{background: :surface, padding: :space_md}}

# Sigil style
~dala(<Box style={@card_style}>...</Box>)

# DSL style (using Dala.UI.box or expression)
{[:box, style: @card_style, children: [...]]}
```

## Migration Between Styles

### Sigil → DSL

1. Add `use Dala.Spark.Dsl` to your module
2. Move state to `attribute` declarations
3. Move render logic to `screen` block
4. Remove manual `mount/3` and `render/1`
5. Convert `{self(), :tag}` to `:tag` atoms
6. Convert `handle_info/2` to `handle_event/3`
7. Use `@ref` syntax for assign references

### DSL → Sigil

1. Replace `use Dala.Spark.Dsl` with `use Dala.Screen`
2. Add manual `mount/3` with `Dala.Socket.assign/3` calls
3. Add manual `render/1` returning `~dala` sigil
4. Convert `:tag` atoms to `{self(), :tag}` tuples
5. Convert `handle_event/3` to `handle_info/2`
6. Replace `@ref` with `assigns.key` or string interpolation

## Best Practices

### Sigil Style

- Pre-compute handler tuples before the sigil
- Use `Dala.UI` helper functions for complex nodes
- Extract reusable UI into component functions
- Keep `render/1` pure — no side effects

### DSL Style

- Use descriptive attribute names
- Leverage `@ref` syntax for cleaner templates
- Keep `handle_event/3` functions focused
- Use the `screen` block for static layouts, expression slots for dynamic content

## Mixing Styles

You can mix both styles in the same project, but not in the same screen module. Choose one style per screen for consistency.

For shared utilities, `Dala.UI` functions work with both styles since they return plain maps:

```elixir
# Works in both sigil and DSL screens
Dala.UI.text(text: "Hello")
```

## Further Reading

- [Components](components.md) — Detailed sigil syntax and component reference
- [Spark DSL](spark_dsl.md) — In-depth DSL documentation
- [Theming](theming.md) — Colors, spacing, and typography tokens
- [Events](events.md) — Event system and message passing
