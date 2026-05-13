# Skill: Generate Dala Screen Modules with DSL Style

## Purpose

This skill teaches an AI agent how to generate Dala screen modules using the
Spark DSL declarative syntax. After reading this document, the agent can
autonomously create complete, correct screen modules without trial-and-error.

---

## 1. Module Skeleton

Every DSL screen module follows this exact structure:

```elixir
defmodule MyApp.SomeScreen do
  use Dala.Spark.Dsl

  dala do
    attribute :key, :type, default: value

    screen name: :screen_atom do
      # UI components here
    end
  end

  # Event handlers below
  def handle_event(:event_atom, _params, socket) do
    {:noreply, socket}
  end
end
```

### Key rules

| Rule | Detail |
|------|--------|
| `use Dala.Spark.Dsl` | Always. Never `use Dala.Screen` for DSL screens. |
| `dala do ... end` | Wraps both `attributes` and `screen` sections. |
| `attributes do ... end` | Optional. Omit if the screen has no state. |
| `screen name: :atom do` | Required. `name:` is a keyword arg. |
| `handle_event/3` | One clause per event atom referenced in `on_tap` / `on_change` / etc. |

### Screen name inference

If you omit `name`, it's automatically inferred from the module name:

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl
  # Inferred name: :counter (removes "Screen" suffix, converts to snake_case)
  screen do
    text "Hello"
  end
end
```

Common suffixes removed: `Screen`, `View`, `Page`.

---

## 2. Attributes Section

Declares screen state. The DSL auto-generates `mount/3` from these.

### Syntax

```elixir
attributes do
  attribute :name, :type, default: value
end
```

### Supported types

| Type | Default example |
|------|----------------|
| `:integer` | `default: 0` |
| `:string` | `default: "Hello"` |
| `:boolean` | `default: false` |
| `:float` | `default: 0.0` |
| `:atom` | `default: :idle` |
| `:list` | `default: []` |
| `:map` | `default: %{}` |

### Rules

- `default` is optional — defaults to `nil`.
- Every attribute becomes an assign, initialised in the generated `mount/3`.
- Do **not** write a manual `mount/3` when using `attributes do`. The transformer
  generates it; a manual definition will clash.

---

## 3. Screen Section

### Required: `name` (keyword arg)

```elixir
screen name: :my_screen do
  # ...
end
```

The `:name` atom identifies the screen in navigation and debugging.
It's passed as a keyword argument to `screen`.

### @ref syntax

Any string prop can embed `@assign_key` to reference a runtime assign:

```elixir
text "Count: @count"          # → "Count: " <> to_string(assigns[:count])
text "@title"                  # → to_string(assigns[:title])
button "Save @item_name"       # → "Save " <> to_string(assigns[:item_name])
```

- `@safe_area` is always available (populated by the framework).
- Use `@safe_area.top`, `@safe_area.bottom` etc. for safe-area insets.

## 3.5 PubSub Section

The `pubsub` section declares topic subscriptions for the screen. Topics are subscribed when the screen mounts and unsubscribed when it terminates.

```elixir
pubsub do
  subscribe "chat:room:123", on_message: :handle_chat
  subscribe "user:456", on_message: :handle_user_event
end
```

- `topic` (string, required) — the PubSub topic to subscribe to
- `on_message` (atom, required) — the handler function name in the screen module

The handler receives the published message as its first argument:

```elixir
def handle_chat({:message, text}, socket) do
  messages = socket.assigns.messages ++ [text]
  {:noreply, Dala.Socket.assign(socket, :messages, messages)}
end
```

Use `Dala.PubSub` to set up a PubSub instance and broadcast messages:

```elixir
# In your app supervision tree:
children = [
  {Dala.PubSub, name: MyApp.PubSub}
]

# Broadcast a message:
Dala.PubSub.broadcast(MyApp.PubSub, "chat:room:123", {:message, "Hello!"})
```

## 3.6 Control Flow (Coming Soon)

Control flow (`if`/`for`) is NOT currently supported in the DSL.
Spark DSL entities are structs, not arbitrary Elixir AST.

For dynamic rendering, use traditional `Dala.Screen` with `render/1` function.

---

## 4. Component Catalogue

### 4.1 Layout containers (support nested children via `do...end`)

Container props go **inside** the `do...end` block, **before** children:

```elixir
column do
  padding :space_md       # ← prop line
  gap :space_sm           # ← prop line
  text "Child 1"          # ← child
  text "Child 2"          # ← child
end
```

#### `column` — vertical stack (VStack)

| Prop | Type | Description |
|------|------|-------------|
| `padding` | token or int | All-side padding |
| `padding_top/right/bottom/left` | token or int | Per-side padding |
| `gap` | token or int | Space between children |
| `background` | token | Background colour |
| `border_color` | token | Border colour |
| `border_width` | int | Border width |
| `corner_radius` | int | Rounded corners |
| `fill_width` | bool | Stretch to fill parent width |
| `width` / `height` | int | Fixed dimensions |
| `on_tap` | atom | Tap handler |
| `on_long_press` | atom | Long-press handler |
| `on_double_tap` | atom | Double-tap handler |
| `on_swipe` | atom | Swipe handler |
| `on_swipe_left/right/up/down` | atom | Directional swipe |
| `accessibility_id` | atom | Test ID |

#### `row` — horizontal stack (HStack)

Same props as `column`. Children are laid out horizontally.

#### `box` — overlapping stack (ZStack)

Same props as `column`. Children overlap (last on top).

#### `scroll` — scrollable container

| Prop | Type | Description |
|------|------|-------------|
| `horizontal` | bool | Horizontal scrolling |
| `show_indicator` | bool | Show scroll indicator |
| `on_end_reached` | atom | Handler when scroll reaches end |
| `on_scroll` | atom | Handler during scrolling |
| `padding` | token or int | Padding |
| `background` | token | Background colour |

#### `modal` — modal overlay

| Prop | Type | Description |
|------|------|-------------|
| `visible` | bool | Show the modal |
| `on_dismiss` | atom | Handler when user dismisses |
| `presentation_style` | `:full_screen` or `:page_sheet` | Presentation style |

#### `pressable` — pressable wrapper

| Prop | Type | Description |
|------|------|-------------|
| `on_press` | atom | Press handler |
| `on_long_press` | atom | Long-press handler |

#### `safe_area` — safe area container

No props. Wraps children to avoid notch/home indicator.

---

### 4.2 Leaf components (no children, props as keyword args)

#### `text`

```elixir
text "Hello, world!"
text "Count: @count", text_size: :xl, text_color: :on_surface
text "Title", font_weight: "bold", text_align: :center
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | string | Text content (supports @ref) |
| `text_color` | token | Text colour |
| `text_size` | token or int | Font size |
| `font_weight` | `"regular"`, `"medium"`, `"semibold"`, `"bold"`, `"light"`, `"thin"` | Weight |
| `font_family` | string | Custom font family |
| `text_align` | `:left`, `:center`, `:right` | Alignment |
| `italic` | bool | Italic style |
| `line_height` | float | Line height multiplier |
| `letter_spacing` | float | Extra letter spacing |
| `padding` | token or int | Padding |
| `padding_top/right/bottom/left` | token or int | Per-side padding |
| `background` | token | Background colour |
| `corner_radius` | int | Rounded corners |
| `fill_width` | bool | Fill parent width |
| `on_tap` | atom | Tap handler |
| `on_long_press` | atom | Long-press handler |
| `on_double_tap` | atom | Double-tap handler |
| `accessibility_id` | atom | Test ID |

#### `button`

```elixir
button "Press me", on_tap: :pressed
button "Submit", on_tap: :submit, background: :primary, text_color: :on_primary
button "Disabled", on_tap: :action, disabled: true
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | string | Label (supports @ref) |
| `on_tap` | atom | Tap handler |
| `disabled` | bool | Disable the button |
| `text_color` | token | Label colour |
| `text_size` | token or int | Font size |
| `font_weight` | string | Font weight |
| `background` | token | Background colour |
| `padding` | token or int | Padding |
| `padding_top/right/bottom/left` | token or int | Per-side padding |
| `corner_radius` | int | Rounded corners |
| `fill_width` | bool | Fill parent width |
| `accessibility_id` | atom | Test ID |

#### `icon`

```elixir
icon "settings", text_size: 24, text_color: :on_surface
icon "chevron_right", on_tap: :navigate
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | string | Icon name (SF Symbols / Material) |
| `text_size` | token or int | Glyph size |
| `text_color` | token | Glyph tint |
| `padding` | token or int | Padding |
| `background` | token | Background colour |
| `on_tap` | atom | Tap handler |
| `on_long_press` | atom | Long-press handler |
| `accessibility_id` | atom | Test ID |

#### `image`

```elixir
image "https://example.com/photo.jpg"
image "logo.png", width: 100, height: 100, resize_mode: :contain
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | string | URL or local asset name |
| `resize_mode` | `:cover`, `:contain`, `:stretch`, `:repeat` | Resize mode |
| `width` / `height` | int | Dimensions |
| `corner_radius` | int | Rounded corners |
| `placeholder_color` | token | Colour while loading |
| `accessibility_id` | atom | Test ID |

#### `video`

```elixir
video "https://example.com/clip.mp4", autoplay: true, loop: true
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | string | Video URL |
| `autoplay` | bool | Auto-play |
| `loop` | bool | Loop playback |
| `controls` | bool | Show controls (default true) |
| `width` / `height` | int | Dimensions |

#### `text_field`

```elixir
text_field placeholder: "Enter name", on_change: :name_changed
text_field keyboard_type: :email, return_key: :next, on_submit: :next_field
```

| Prop | Type | Description |
|------|------|-------------|
| `text` | string | Current text value |
| `placeholder` | string | Placeholder when empty |
| `on_change` | atom | Handler for text changes |
| `on_focus` | atom | Handler when focused |
| `on_blur` | atom | Handler when blurred |
| `on_submit` | atom | Handler for return key |
| `on_compose` | atom | Handler for IME composition |
| `keyboard_type` | `:default`, `:number`, `:decimal`, `:email`, `:phone`, `:url` | Keyboard type |
| `return_key` | `:done`, `:next`, `:go`, `:search`, `:send` | Return key type |
| `text_color` | token | Text colour |
| `text_size` | token or int | Font size |
| `background` | token | Background colour |
| `padding` | token or int | Padding |
| `corner_radius` | int | Rounded corners |
| `accessibility_id` | atom | Test ID |

#### `toggle`

```elixir
toggle value: true, on_change: :notifications_toggled, text: "Notifications"
```

| Prop | Type | Description |
|------|------|-------------|
| `value` | bool | On/off state |
| `on_change` | atom | Handler for value changes |
| `text` | string | Label beside the switch |
| `track_color` | token | Track colour when on |
| `thumb_color` | token | Thumb colour |
| `accessibility_id` | atom | Test ID |

#### `slider`

```elixir
slider value: 0.5, min_value: 0, max_value: 100, on_change: :volume_changed
```

| Prop | Type | Description |
|------|------|-------------|
| `value` | float | Current value |
| `min_value` | float | Minimum (default 0.0) |
| `max_value` | float | Maximum (default 1.0) |
| `on_change` | atom | Handler for value changes |
| `color` | token | Slider tint colour |
| `accessibility_id` | atom | Test ID |

#### `switch` (legacy — prefer `toggle`)

```elixir
switch value: true, on_toggle: :toggled
```

#### `divider`

```elixir
divider()
divider thickness: 2, color: :primary
```

| Prop | Type | Description |
|------|------|-------------|
| `thickness` | float | Line thickness (default 1.0) |
| `color` | token | Divider colour (default :border) |
| `padding` | token or int | Padding around divider |

#### `spacer`

```elixir
spacer()          # flexible spacer
spacer size: 20   # fixed 20pt spacer
```

| Prop | Type | Description |
|------|------|-------------|
| `size` | int | Fixed size in pt (omit for flexible) |

#### `activity_indicator`

```elixir
activity_indicator size: :large, color: :primary
```

| Prop | Type | Description |
|------|------|-------------|
| `size` | `:small`, `:large` | Spinner size |
| `color` | token | Spinner colour |
| `animating` | bool | Whether animating |

#### `progress_bar`

```elixir
progress_bar progress: 0.7, color: :primary
```

| Prop | Type | Description |
|------|------|-------------|
| `progress` | float | Progress 0.0–1.0 |
| `indeterminate` | bool | Indeterminate spinner |
| `color` | token | Bar colour |

#### `status_bar`

```elixir
status_bar bar_style: :light_content, hidden: false
```

| Prop | Type | Description |
|------|------|-------------|
| `bar_style` | `:default`, `:light_content` | Status bar style |
| `hidden` | bool | Hide the status bar |

#### `refresh_control`

```elixir
refresh_control on_refresh: :reload, refreshing: false
```

| Prop | Type | Description |
|------|------|-------------|
| `on_refresh` | atom | Pull-to-refresh handler |
| `refreshing` | bool | Whether refresh is in progress |
| `tint_color` | token | Spinner tint colour |

#### `webview`

```elixir
webview "https://elixir-lang.org"
webview "https://example.com", show_url: true, width: 400, height: 600
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | string | URL to load |
| `allow` | list of strings | Allowed URL prefixes |
| `show_url` | bool | Show URL label above |
| `title` | string | Static title (overrides show_url) |
| `width` / `height` | int | Dimensions |

#### `camera_preview`

```elixir
camera_preview facing: :front, width: 300, height: 400
```

| Prop | Type | Description |
|------|------|-------------|
| `facing` | `:back`, `:front` | Camera facing (default :back) |
| `width` / `height` | int | Dimensions |

#### `native_view`

```elixir
native_view MyApp.ChartComponent, id: :revenue_chart
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | atom (module) | Component module (implements Dala.Ui.NativeView) |
| `id` | atom (required) | Unique identifier per screen |

#### `tab_bar`

```elixir
tab_bar tabs: [%{id: "home", label: "Home", icon: "home"}], active_tab: "home", on_tab_select: :tab_changed
```

| Prop | Type | Description |
|------|------|-------------|
| `tabs` | any | List of `%{id, label, icon?}` maps |
| `active_tab` | string | Selected tab id |
| `on_tab_select` | atom | Handler for tab selection |
| `accessibility_id` | atom | Test ID |

#### `list`

```elixir
list :my_list, data: @items, on_end_reached: :load_more
```

| Prop | Type | Description |
|------|------|-------------|
| *(1st arg)* | atom (required) | List identifier for selection events |
| `data` | any | Enumerable of items (supports @ref) |
| `on_end_reached` | atom | Handler when list reaches end |
| `scroll` | bool | Enable scrolling (default true) |
| `accessibility_id` | atom | Test ID |

---

## 5. Event Handling

### `handle_event/3` — Primary callback for DSL screens

Every `on_tap`, `on_change`, `on_press`, etc. prop must have a matching
`handle_event/3` clause:

```elixir
def handle_event(:save, _params, socket) do
  # ... logic ...
  {:noreply, socket}
end
```

### Change events

Components that produce values (text_field, toggle, slider) send change events
as `{:change, handler_atom, value}`:

```elixir
# In the screen block:
text_field placeholder: "Enter name", on_change: :name_changed

# Handler:
def handle_event({:change, :name_changed, value}, _params, socket) do
  {:noreply, Dala.Socket.assign(socket, :name, value)}
end

### `handle_info/2` — Device API results and raw messages

Device results (camera, location, etc.) and other process messages arrive via
`handle_info/2`:

```elixir
def handle_info({:camera, :photo, %{path: path}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :photo_path, path)}
end
```

### Navigation from event handlers

```elixir
def handle_event(:open_detail, _params, socket) do
  {:noreply, Dala.Socket.push_screen(socket, MyApp.DetailScreen, %{id: socket.assigns.id})}
end

def handle_event(:go_back, _params, socket) do
  {:noreply, Dala.Socket.pop_screen(socket)}
end
```

---

## 6. Common Patterns

### 6.1 Counter screen

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl

  dala do
    attributes do
      attribute :count, :integer, default: 0
    end

    screen do
      name :counter
      column do
        padding :space_md
        gap :space_sm
        text "Count: @count", text_size: :xl
        row do
          gap :space_sm
          button "−", on_tap: :decrement
          button "+", on_tap: :increment
        end
      end
    end
  end

  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event(:decrement, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count - 1)}
  end
end
```

### 6.2 Form screen

```elixir
defmodule MyApp.FormScreen do
  use Dala.Spark.Dsl

  dala do
    attributes do
      attribute :name, :string, default: ""
      attribute :email, :string, default: ""
      attribute :submitting, :boolean, default: false
    end

    screen do
      name :form
      column do
        padding :space_md
        gap :space_md
        text "Contact Form", text_size: :xl, font_weight: "bold"
        text_field placeholder: "Name", on_change: :name_changed
        text_field placeholder: "Email", keyboard_type: :email, on_change: :email_changed
        button "Submit", on_tap: :submit, disabled: true
      end
    end
  end

  def handle_event({:change, :name_changed, value}, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :name, value)}
  end

  def handle_event({:change, :email_changed, value}, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :email, value)}
  end

  def handle_event(:submit, _params, socket) do
    # ... submit logic ...
    {:noreply, Dala.Socket.assign(socket, :submitting, true)}
  end
end
```

### 6.3 List screen with navigation

```elixir
defmodule MyApp.ListScreen do
  use Dala.Spark.Dsl

  dala do
    attributes do
      attribute :items, :list, default: []
      attribute :loading, :boolean, default: false
    end

    screen do
      name :item_list
      column do
        padding :space_md
        gap :space_sm
        text "Items", text_size: :xl, font_weight: "bold"
        list :items, data: @items, on_end_reached: :load_more
      end
    end
  end

  def handle_event(:load_more, _params, socket) do
    # ... fetch more items ...
    {:noreply, socket}
  end
end
```

### 6.4 Modal screen

```elixir
defmodule MyApp.ModalScreen do
  use Dala.Spark.Dsl

  dala do
    attributes do
      attribute :show_modal, :boolean, default: false
      attribute :result, :string, default: ""
    end

    screen do
      name :modal_demo
      column do
        padding :space_md
        gap :space_sm
        text "Modal Demo", text_size: :xl
        button "Open Modal", on_tap: :open_modal
        text "Result: @result"
      end
      modal do
        visible true
        on_dismiss :dismissed
        column do
          padding :space_md
          gap :space_sm
          text "Modal Content", text_size: :lg
          button "Close", on_tap: :close_modal
        end
      end
    end
  end

  def handle_event(:open_modal, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :show_modal, true)}
  end

  def handle_event(:close_modal, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :show_modal, false)}
  end

  def handle_event(:dismissed, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :show_modal, false)}
  end
end
```

### 6.5 Safe area with scrollable content

```elixir
defmodule MyApp.ScrollScreen do
  use Dala.Spark.Dsl

  dala do
    attributes do
      attribute :content, :string, default: "Long content here..."
    end

    screen do
      name :scrollable
      safe_area do
        scroll do
          padding :space_md
          text "@content"
        end
      end
    end
  end
end
```

---

## 7. Registration in Dala.App

Every screen module must be registered in the app's `navigation/1` callback:

```elixir
defmodule MyApp do
  use Dala.App

  def navigation(_platform) do
    screens([MyApp.HomeScreen, MyApp.DetailScreen, MyApp.SettingsScreen])
    stack(:home, root: MyApp.HomeScreen, title: "Home")
  end
end
```

- `screens/1` validates at compile time that each module is a valid Dala.Screen.
- `stack/2` declares the navigation stack with a root screen.
- For tab-based apps, use `tab_bar/1` or `drawer/1` containing multiple `stack/2` calls.

---

## 8. Compile-Time Verification

The DSL verifier checks at compile time:

1. **Event handler props must be atoms** — `on_tap: :save` (not `on_tap: "save"`).
2. **Attribute types must be valid** — one of `:integer`, `:string`, `:boolean`,
   `:float`, `:atom`, `:list`, `:map`.
3. **`name` is required** in the `screen` block.

If any check fails, compilation stops with a descriptive error.

---

## 9. Generated Functions

The DSL transformers auto-generate two functions. **Never write these manually**
when using the DSL:

### `mount/3`

```elixir
def mount(_params, _session, socket) do
  socket = Dala.Socket.assign(socket, :count, 0)
  socket = Dala.Socket.assign(socket, :message, "Hello")
  {:ok, socket}
end
```

Generated from `attributes do`. If no attributes, a minimal `mount/3` returning
`{:ok, socket}` is still generated.

### `render/1`

```elixir
def render(assigns) do
  [
    %{type: :column, props: %{gap: :space_sm}, children: [
      %{type: :text, props: %{text: "Count: " <> to_string(assigns[:count])}, children: []},
      %{type: :button, props: %{text: "Increment", on_tap: :increment}, children: []}
    ]}
  ]
end
```

Generated from the `screen do` block. Returns a list of node maps.

---

## 10. Migration from Manual Screens

| Manual | DSL |
|--------|-----|
| `use Dala.Screen` | `use Dala.Spark.Dsl` |
| Manual `mount/3` with `assign/3` calls | `attributes do attribute :key, :type, default: val end` |
| Manual `render/1` returning widget maps | `screen do name :x; column do ... end end` |
| `Dala.Ui.Widgets.text(text: "Hello")` | `text "Hello"` |
| `Dala.Ui.Widgets.column([padding: 16], [...])` | `column do padding 16; text "Hello" end` |
| `handle_event/3` | Same — keep as-is |
| `handle_info/2` | Same — keep as-is |

---

## 11. Anti-Patterns to Avoid

| Anti-pattern | Why | Fix |
|-------------|-----|-----|
| Writing `mount/3` manually in a DSL screen | Clashes with generated mount | Use `attributes do` |
| Writing `render/1` manually in a DSL screen | Clashes with generated render | Use `screen do` |
| `use Dala.Screen` in a DSL screen | Missing DSL extension | Use `use Dala.Spark.Dsl` |
| `on_tap: "save"` (string) | Verifier rejects non-atom | Use `on_tap: :save` |
| `attribute :count, :int` | Invalid type | Use `:integer` |
| Props after children in a container | Spark parses top-down | Put all props before children |
| `@count` outside a string | Only works inside string literals | Use `assigns.count` in code, `@count` in strings |
| Missing `handle_event/3` for an event | Runtime crash on tap | Add a clause for every event atom |

---

## 12. Quick-Reference Checklist

When generating a new screen module, verify:

- [ ] `use Dala.Spark.Dsl` at the top
- [ ] `dala do ... end` wraps everything
- [ ] `attributes do` declares all state (or omitted if stateless)
- [ ] `screen do` contains `name :atom` as first entity
- [ ] Container props appear before children inside `do...end`
- [ ] Leaf components use keyword args, not `do...end`
- [ ] Every `on_tap`/`on_change`/`on_press` atom has a `handle_event/3` clause
- [ ] No manual `mount/3` or `render/1` — the DSL generates them
- [ ] Screen is registered in `Dala.App.navigation/1` via `screens/1`
