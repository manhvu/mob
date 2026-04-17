# Components

There are two equivalent ways to write Mob UI — plain Elixir maps and the `~MOB` sigil. Both produce identical output; choose whichever feels natural.

## Map syntax

```elixir
%{
  type:     :column,           # atom — determines native widget
  props:    %{padding: 16},    # map  — styling and behaviour
  children: [...]              # list — nested components
}
```

Maps are idiomatic Elixir and compose naturally with `Enum.map`, pattern matching, and helper functions.

## Sigil syntax

```elixir
import Mob.Sigil

~MOB"""
<Column padding={16}>
  <Text text="Hello" text_size={:xl} />
  <Button text="Save" on_tap={{self(), :save}} />
</Column>
"""
```

The `~MOB` sigil compiles to the same maps at compile time — there is no runtime overhead or interpretation. It is a good fit for layouts that are mostly static structure, and for developers coming from LiveView or web backgrounds.

Expression attributes use `{...}` and support any Elixir expression including nested maps and function calls. Expression child slots also use `{...}` and accept a single node map or a list:

```elixir
~MOB"""
<Column>
  {Enum.map(assigns.items, fn item ->
    ~MOB(<Text text={item} />)
  end)}
</Column>
"""
```

The two styles are fully interchangeable — you can mix them freely in the same `render/1` function.

---

`Mob.Renderer` serialises the component tree to JSON and passes it to the native side in a single NIF call. Compose (Android) and SwiftUI (iOS) handle diffing and rendering.

## Prop values

Props accept:

- **Integers and floats** — used as-is (dp on Android, pt on iOS)
- **Strings** — used as-is
- **Booleans** — used as-is
- **Color atoms** (`:primary`, `:blue_500`, etc.) — resolved via the active theme and the base palette to ARGB integers. See [Theming](theming.md).
- **Spacing tokens** (`:space_xs`, `:space_sm`, `:space_md`, `:space_lg`, `:space_xl`) — scaled by `theme.space_scale` and resolved to integers.
- **Radius tokens** (`:radius_sm`, `:radius_md`, `:radius_lg`, `:radius_pill`) — resolved to integers from the active theme.
- **Text size tokens** (`:xs`, `:sm`, `:base`, `:lg`, `:xl`, `:2xl`, `:3xl`, `:4xl`, `:5xl`, `:6xl`) — scaled by `theme.type_scale` and resolved to floats.

## Platform-specific props

Wrap props in `:ios` or `:android` to apply them only on that platform:

```elixir
props: %{
  padding: 12,
  ios: %{padding: 20}   # iOS sees 20; Android sees 12
}
```

## Layout components

### `:column`

Stacks children vertically.

| Prop | Type | Description |
|------|------|-------------|
| `padding` | number / token | Uniform padding |
| `padding_top`, `padding_bottom`, `padding_left`, `padding_right` | number / token | Per-side padding |
| `gap` | number / token | Space between children |
| `background` | color | Background color |
| `fill_width` | boolean | Stretch to fill available width (default `true`) |
| `fill_height` | boolean | Stretch to fill available height |
| `align` | `:start` / `:center` / `:end` | Cross-axis alignment of children |

### `:row`

Lays out children horizontally.

| Prop | Type | Description |
|------|------|-------------|
| `padding` | number / token | Uniform padding |
| `gap` | number / token | Space between children |
| `background` | color | Background color |
| `fill_width` | boolean | Stretch to fill available width |
| `align` | `:start` / `:center` / `:end` | Cross-axis alignment of children |

### `:box`

A single-child container. Use it to add background, padding, or corner radius to a child:

```elixir
%{
  type: :box,
  props: %{background: :surface, padding: :space_md, corner_radius: :radius_md},
  children: [
    %{type: :text, props: %{text: "Card content"}, children: []}
  ]
}
```

| Prop | Type | Description |
|------|------|-------------|
| `padding` | number / token | Uniform padding |
| `background` | color | Background color |
| `corner_radius` | number / token | Corner radius |
| `fill_width` | boolean | Stretch to fill available width |

### `:scroll`

A vertically scrolling container.

| Prop | Type | Description |
|------|------|-------------|
| `padding` | number / token | Padding inside the scroll area |
| `background` | color | Background color |

### `:spacer`

Fills available space in a row or column. No props.

```elixir
%{type: :row, props: %{}, children: [
  %{type: :text,   props: %{text: "Left"},  children: []},
  %{type: :spacer, props: %{},              children: []},
  %{type: :text,   props: %{text: "Right"}, children: []}
]}
```

## List components

### `:list`

A platform-native scrolling list optimised for rendering many rows efficiently. Prefer this over `:scroll` + `:column` for any list of more than ~20 items.

| Prop | Type | Description |
|------|------|-------------|
| `items` | list | Data items. Each renders as a child. |
| `on_select` | `{pid, tag}` | Called when a row is tapped: `{:select, tag, index}` |

```elixir
%{
  type: :list,
  props: %{items: assigns.names, on_select: {self(), :name_selected}},
  children: Enum.map(assigns.names, fn name ->
    %{type: :text, props: %{text: name, padding: :space_md}, children: []}
  end)
}
```

### `:lazy_list`

A virtualized list that renders rows on demand. Supports `on_end_reached` for pagination.

| Prop | Type | Description |
|------|------|-------------|
| `on_end_reached` | `{pid, tag}` | Fired when the user scrolls near the end: `{:tap, {tag, nil}}` |

## Content components

### `:text`

Displays a string.

| Prop | Type | Description |
|------|------|-------------|
| `text` | string | The text to display (required) |
| `text_size` | number / token | Font size |
| `text_color` | color | Text color |
| `font_weight` | `"regular"` / `"medium"` / `"bold"` | Font weight |
| `text_align` | `:start` / `:center` / `:end` | Horizontal alignment |

### `:button`

A tappable button. Has sensible defaults injected by the renderer (primary background, on_primary text, medium radius, fill width).

| Prop | Type | Description |
|------|------|-------------|
| `text` | string | Button label |
| `on_tap` | pid / `{pid, tag}` | Tap handler. Tag becomes the `"tag"` key in `handle_event` params. |
| `background` | color | Background color (default `:primary`) |
| `text_color` | color | Label color (default `:on_primary`) |
| `text_size` | number / token | Font size (default `:base`) |
| `font_weight` | string | Font weight (default `"medium"`) |
| `padding` | number / token | Padding (default `:space_md`) |
| `corner_radius` | number / token | Corner radius (default `:radius_md`) |
| `fill_width` | boolean | Fill available width (default `true`) |
| `disabled` | boolean | Disable tap interaction |

```elixir
%{type: :button, props: %{text: "Save",   on_tap: {self(), :save}},   children: []}
%{type: :button, props: %{text: "Cancel", on_tap: {self(), :cancel},
                          background: :surface, text_color: :on_surface}, children: []}
```

### `:text_field`

An editable text input. Has defaults injected by the renderer (surface_raised background, border, small radius).

| Prop | Type | Description |
|------|------|-------------|
| `value` | string | Current text (controlled) |
| `placeholder` | string | Hint text when empty |
| `on_change` | `{pid, tag}` | Fires as the user types: params include `"value"` |
| `on_submit` | `{pid, tag}` | Fires on keyboard return |
| `on_focus` | `{pid, tag}` | Fires when the field gains focus |
| `on_blur` | `{pid, tag}` | Fires when the field loses focus |
| `secure` | boolean | Password masking |
| `keyboard_type` | `:default` / `:email` / `:number` / `:phone` | Keyboard variant |
| `background` | color | Background (default `:surface_raised`) |
| `text_color` | color | Input text color (default `:on_surface`) |
| `placeholder_color` | color | Placeholder color (default `:muted`) |
| `border_color` | color | Border color (default `:border`) |
| `padding` | number / token | Padding (default `:space_sm`) |
| `corner_radius` | number / token | Corner radius (default `:radius_sm`) |

### `:divider`

A horizontal rule. Default color is `:border`.

| Prop | Type | Description |
|------|------|-------------|
| `color` | color | Line color (default `:border`) |

### `:progress`

An indeterminate activity indicator (spinner).

| Prop | Type | Description |
|------|------|-------------|
| `color` | color | Indicator color (default `:primary`) |

## Using `Mob.Style` for reusable styles

Define shared styles as module attributes and attach them via the `:style` prop. Inline props override style values:

```elixir
@card_style %Mob.Style{props: %{background: :surface, padding: :space_md, corner_radius: :radius_md}}
@title_style %Mob.Style{props: %{text_size: :xl, font_weight: "bold", text_color: :on_surface}}

def render(assigns) do
  %{type: :box, props: %{style: @card_style}, children: [
    %{type: :text, props: %{style: @title_style, text: assigns.title}, children: []},
    %{type: :text, props: %{text: assigns.body,  text_color: :muted,  text_size: :sm}, children: []}
  ]}
end
```

## Component constructors

`Mob.UI` provides constructor functions as an alternative to writing maps directly:

```elixir
import Mob.UI

text(text: "Hello", text_size: :xl)
#=> %{type: :text, props: %{text: "Hello", text_size: :xl}, children: []}
```

Currently `Mob.UI` covers `:text`. Maps are preferred for full component control.

## Tap handler conventions

Use tagged tuples for tap handlers so you can pattern-match on the tag in `handle_info/2`:

```elixir
# In render:
on_tap: {self(), :save}

# In handle_info:
def handle_info({:tap, :save}, socket) do
  ...
end
```

Using a bare `pid` works but loses the tag:

```elixir
on_tap: self()
# handle_info receives {:tap, nil}
```

## Event routing

**All events are delivered to the screen process.** `self()` inside `render/1` is always the screen's GenServer pid, so every `on_tap`, `on_change`, `on_select`, and similar handler sends its message to the screen's `handle_info/2`.

```elixir
# These two are equivalent — both deliver {:tap, :save} to the screen
on_tap: {self(), :save}
on_tap: self()   # tag is nil
```

This holds regardless of nesting. A `:button` buried inside a `:scroll` inside a `:column` still sends its tap event to the screen, not to any intermediate container.

For `:list` rows the message shape is `{:select, tag, index}`:

```elixir
props: %{on_select: {self(), :item_tapped}}

def handle_info({:select, :item_tapped, index}, socket) do
  ...
end
```

### Sub-component event isolation (planned, not yet implemented)

A future `Mob.Component` wrapper will allow a subtree of the render tree to have its own `handle_info/2`, routing events to that component process instead of the screen. The design is:

```elixir
# Future — not available yet
%{type: :component, props: %{module: MyWidget}, children: [...]}
```

Until then, use the `tag` field to distinguish events from different parts of the same screen:

```elixir
%{type: :button, props: %{text: "Top Save",    on_tap: {self(), :top_save}},    children: []}
%{type: :button, props: %{text: "Bottom Save", on_tap: {self(), :bottom_save}}, children: []}
```
