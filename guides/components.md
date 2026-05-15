# Components

## DSL syntax

Screens are defined using the Spark DSL inside a `dala do ... end` block. UI components are declared as nested entities with keyword props:

```elixir
defmodule MyApp.HomeScreen do
  use Dala.Spark.Dsl

  dala do
    attribute :count, :integer, default: 0

    screen name: :home do
      column padding: :space_md, gap: :space_sm do
        text "Hello", text_size: :xl
        button "Save", on_tap: :save
      end
    end
  end

  def handle_event(:save, _params, socket) do
    {:noreply, socket}
  end
end
```

You can also build component trees as plain maps — useful when constructing UI programmatically:

```elixir
%{
  type:     :column,
  props:    %{padding: 16},
  children: [
    %{type: :text,   props: %{text: "Hello", text_size: :xl}, children: []},
    %{type: :button, props: %{text: "Save",  on_tap: {self(), :save}}, children: []}
  ]
}
```

The two styles are fully interchangeable — you can mix them freely in the same `render/1` function.

---

`Dala.Renderer` serialises the component tree to binary via the custom binary protocol and passes it to the native side in a single NIF call. Compose (Android) and SwiftUI (iOS) handle diffing and rendering.

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
column padding: 12, ios: [padding: 20] do
  text "Content"
end
```

## Layout components

### `:column`

Stacks children vertically (VStack equivalent).

| Prop | Type | Description |
|------|------|-------------|
| `padding` | number / token | Uniform padding |
| `padding_top`, `padding_bottom`, `padding_left`, `padding_right` | number / token | Per-side padding |
| `gap` | number / token | Space between children |
| `background` | color | Background color |
| `border_color`, `border_width` | color, number | Border styling |
| `corner_radius` | number / token | Rounded corners |
| `fill_width` | boolean | Stretch to fill available width (default `true`) |
| `width`, `height` | number | Explicit dimensions |
| `alignment` | `:start` / `:center` / `:end` | Cross-axis alignment of children |
| `justify` | `:start` / `:center` / `:end` / `:space_between` / `:space_around` / `:space_evenly` | Main-axis distribution |
| `on_tap`, `on_long_press`, `on_double_tap`, `on_swipe*` | `{pid, tag}` | Gesture handlers |
| `accessibility_id` | string | Test identifier |

```elixir
column padding: :space_md, gap: :space_sm, alignment: :center do
  text "Title"
  text "Subtitle"
end
```

### `:row`

Lays out children horizontally (HStack equivalent).

| Prop | Type | Description |
|------|------|-------------|
| `padding` | number / token | Uniform padding |
| `padding_top`, `padding_bottom`, `padding_left`, `padding_right` | number / token | Per-side padding |
| `gap` | number / token | Space between children |
| `background` | color | Background color |
| `border_color`, `border_width` | color, number | Border styling |
| `corner_radius` | number / token | Rounded corners |
| `fill_width` | boolean | Stretch to fill available width |
| `width`, `height` | number | Explicit dimensions |
| `alignment` | `:start` / `:center` / `:end` | Cross-axis alignment of children |
| `justify` | `:start` / `:center` / `:end` / `:space_between` / `:space_around` / `:space_evenly` | Main-axis distribution |
| `on_tap`, `on_long_press`, `on_double_tap`, `on_swipe*` | `{pid, tag}` | Gesture handlers |
| `accessibility_id` | string | Test identifier |

To distribute children evenly across a row, give each child a `weight` prop (analogous to `flex: 1` in CSS):

```elixir
row fill_width: true do
  button "Cancel", on_tap: :cancel, weight: 1, background: :surface, text_color: :on_surface
  spacer size: 8
  button "Save", on_tap: :save, weight: 1
end
```

### `:box`

A stacking container (ZStack equivalent). Children are layered on top of each other. Use it for overlays, badges, and absolute positioning.

| Prop | Type | Description |
|------|------|-------------|
| `padding` | number / token | Uniform padding |
| `padding_top`, `padding_bottom`, `padding_left`, `padding_right` | number / token | Per-side padding |
| `background` | color | Background color |
| `border_color`, `border_width` | color, number | Border styling |
| `corner_radius` | number / token | Rounded corners |
| `fill_width` | boolean | Stretch to fill available width |
| `width`, `height` | number | Explicit dimensions |
| `on_tap`, `on_long_press`, `on_double_tap`, `on_swipe*` | `{pid, tag}` | Gesture handlers |
| `accessibility_id` | string | Test identifier |

```elixir
box background: :surface, padding: :space_md, corner_radius: :radius_md do
  text "Card content"
end
```

### `:scroll`

A scrolling container (ScrollView equivalent).

| Prop | Type | Description |
|------|------|-------------|
| `direction` | `:vertical` / `:horizontal` | Scroll direction (default `:vertical`) |
| `shows_indicator` | boolean | Show scroll indicator (default `true`) |
| `on_end_reached` | `{pid, tag}` | Fired when scroll reaches bottom/end |
| `on_scroll` | `{pid, tag}` | Fired during scrolling with scroll position |
| `paging` | boolean | Enable snap-to-page scrolling (default `false`) |
| `padding` | number / token | Padding inside the scroll area |
| `background` | color | Background color |

```elixir
scroll padding: :space_md do
  text "Long content..."
end
```

### `:spacer`

Inserts fixed space in a row or column, or fills available space when no `size` is given.

| Prop | Type | Description |
|------|------|-------------|
| `size` | number | Fixed size in dp/pt. Omit to fill remaining space. |

```elixir
# Fixed gap:
spacer size: 16

# Push children to opposite ends of a row:
row do
  text "Left"
  spacer
  text "Right"
end
```

### `:safe_area`

Renders children within safe area boundaries (avoiding notches, status bar, etc.).

```elixir
safe_area do
  column padding: :space_md do
    text "Safe content"
  end
end
```

### `:pressable`

A pressable wrapper. Makes any child tappable.

| Prop | Type | Description |
|------|------|-------------|
| `on_press` | `{pid, tag}` | Fired when pressed |
| `on_long_press` | `{pid, tag}` | Fired on long press |

```elixir
pressable on_press: {self(), :card_tapped} do
  text "Tap me"
end
```

## List components

### `:list`

A platform-native scrolling list optimised for rendering many rows efficiently. Prefer this over `:scroll` + `:column` for any list of more than ~20 items.

| Prop | Type | Description |
|------|------|-------------|
| `id` | atom | List identifier for selection events (required) |
| `data` | list | Data items. Each renders as a child. |
| `on_end_reached` | `{pid, tag}` | Event handler when list reaches end |
| `scroll` | boolean | Enable scrolling (default `true`) |

```elixir
list :my_list, data: @items, on_end_reached: :load_more do
  text "Item"
end
```

### `:lazy_list`

A virtualized list that renders rows on demand. Supports `on_end_reached` for pagination.

| Prop | Type | Description |
|------|------|-------------|
| `on_end_reached` | atom | Event handler when the user scrolls near the end |

## Content components

### `:text`

Displays a string.

| Prop | Type | Description |
|------|------|-------------|
| `text` | string | The text to display (required, positional arg) |
| `text_size` | number / token | Font size |
| `text_color` | color | Text color |
| `font_weight` | `"regular"` / `"medium"` / `"semibold"` / `"bold"` / `"light"` / `"thin"` | Font weight |
| `font_family` | string | Custom font family name (nil = system font) |
| `text_align` | `:left` / `:center` / `:right` | Horizontal alignment |
| `italic` | boolean | Italic style |
| `line_height` | float | Line height multiplier (e.g. `1.5` for 150%) |
| `letter_spacing` | float | Extra letter spacing in pt |
| `padding`, `padding_top`, `padding_right`, `padding_bottom`, `padding_left` | number / token | Padding |
| `background` | color | Background color |
| `corner_radius` | number / token | Rounded corners |
| `fill_width` | boolean | Stretch to fill parent width |
| `on_tap`, `on_long_press`, `on_double_tap` | `{pid, tag}` | Gesture handlers |
| `accessibility_id` | string | Test identifier |

```elixir
text "Hello, world!"
text "Count: @count", text_size: :xl, text_color: :on_surface
```

### `:button`

A tappable button. Has sensible defaults injected by the renderer (primary background, on_primary text, medium radius, fill width).

| Prop | Type | Description |
|------|------|-------------|
| `text` | string | Button label (required). Also accepts `:title` for backward compatibility. |
| `on_tap` | `{pid, tag}` | Tap handler. Delivers event to `handle_event/3`. |
| `disabled` | boolean | Disable tap interaction |
| `variant` | `:filled` / `:filled_tonal` / `:outlined` / `:elevated` / `:text` | Button style variant (default `:filled`) |
| `icon` | string | Icon name displayed before the label |
| `elevation` | float | Shadow depth for elevated variant |
| `background` | color | Background color (default `:primary`) |
| `text_color` | color | Label color (default `:on_primary`) |
| `text_size` | number / token | Font size (default `:base`) |
| `font_weight` | string | Font weight (default `"medium"`) |
| `padding`, `padding_top`, `padding_right`, `padding_bottom`, `padding_left` | number / token | Padding |
| `corner_radius` | number / token | Corner radius (default `:radius_md`) |
| `fill_width` | boolean | Fill available width (default `true`) |
| `accessibility_id` | string | Test identifier |

```elixir
button "Save", on_tap: :save
button "Cancel", on_tap: :cancel, background: :surface, text_color: :on_surface
button "Edit", on_tap: :edit, variant: :outlined, icon: "edit"
button "Delete", on_tap: :delete, variant: :text, text_color: :error
```

### `:text_field`

An editable text input. Has defaults injected by the renderer (surface_raised background, border, small radius).

| Prop | Type | Description |
|------|------|-------------|
| `text` | string | Current text (controlled) |
| `placeholder` | string | Hint text when empty |
| `on_change` | `{pid, tag}` | Fires as the user types. Delivers `{:change, tag, value}`. |
| `on_submit` | `{pid, tag}` | Fires on keyboard return. |
| `on_focus` | `{pid, tag}` | Fires when the field gains focus. |
| `on_blur` | `{pid, tag}` | Fires when the field loses focus. |
| `on_compose` | `{pid, tag}` | IME composition events (CJK, etc.) |
| `keyboard_type` | `:default` / `:number` / `:decimal` / `:email` / `:phone` / `:url` | Keyboard variant |
| `return_key` | `:done` / `:next` / `:go` / `:search` / `:send` | Return key type |
| `secure` | boolean | Mask input (password field) |
| `max_length` | integer | Maximum character count |
| `auto_capitalize` | `:none` / `:sentences` / `:words` / `:characters` | Auto-capitalization behaviour |
| `auto_correct` | boolean | Enable/disable auto-correct |
| `min_lines` | integer | Minimum visible lines |
| `max_lines` | integer | Maximum visible lines (nil = unlimited) |
| `text_color` | color | Input text color (default `:on_surface`) |
| `text_size` | number / token | Font size |
| `background` | color | Background (default `:surface_raised`) |
| `padding` | number / token | Padding |
| `corner_radius` | number / token | Corner radius |
| `accessibility_id` | string | Test identifier |

```elixir
text_field placeholder: "Enter name", on_change: :name_changed
text_field placeholder: "Password", secure: true, on_change: :password_changed
text_field placeholder: "Email", keyboard_type: :email, return_key: :next, on_submit: :next_field
```

### `:icon`

Displays a platform-native icon. Logical icon names are resolved to SF Symbols on iOS and Material Symbols on Android.

| Prop | Type | Description |
|------|------|-------------|
| `name` | string | Logical icon name or raw identifier (required) |
| `text_size` | number | Glyph size in sp |
| `text_color` | color | Glyph tint color |
| `padding` | number / token | Padding around icon |
| `background` | color | Background color |
| `on_tap`, `on_long_press` | `{pid, tag}` | Gesture handlers |
| `accessibility_id` | string | Test identifier (also used as accessibility label) |

**Logical icon names:** `settings`, `back`, `forward`, `close`, `add`, `remove`, `edit`, `check`, `chevron_right`, `chevron_left`, `chevron_up`, `chevron_down`, `info`, `warning`, `error`, `search`, `trash`, `share`, `more`, `menu`, `refresh`, `favorite`, `favorite_filled`, `star`, `star_filled`, `user`, `home`

```elixir
icon name: "settings", text_size: 24, text_color: :on_surface
icon name: "chevron_right", on_tap: {self(), :navigate}
```

### `:divider`

A horizontal or vertical divider line.

| Prop | Type | Description |
|------|------|-------------|
| `thickness` | float | Line thickness in pt (default `1.0`) |
| `color` | color | Divider color (default `:border`) |
| `padding` | number / token | Padding around the divider |

```elixir
divider
divider thickness: 2, color: :primary
```

### `:image`

Displays an image from a URL or local asset.

| Prop | Type | Description |
|------|------|-------------|
| `src` | string | URL or local asset name (required) |
| `resize_mode` | `:cover` / `:contain` / `:stretch` / `:repeat` | Resize mode (default `:cover`) |
| `width`, `height` | number | Dimensions in dp/pt; omit to auto-size |
| `corner_radius` | number / token | Rounded corners |
| `placeholder_color` | color | Color shown while loading |
| `on_error` | `{pid, tag}` | Fired when image fails to load |
| `on_load` | `{pid, tag}` | Fired when image finishes loading |
| `accessibility_id` | string | Test identifier |

```elixir
image src: "https://example.com/photo.jpg", resize_mode: :cover, corner_radius: 12
```

### `:video`

An inline video player.

| Prop | Type | Description |
|------|------|-------------|
| `src` | string | Video URL (required) |
| `autoplay` | boolean | Start playing immediately (default `false`) |
| `loop` | boolean | Loop playback (default `false`) |
| `controls` | boolean | Show playback controls (default `true`) |
| `width`, `height` | number | Dimensions in dp/pt; omit to fill parent |

```elixir
video src: "https://example.com/clip.mp4", autoplay: true, loop: true
```

### `:progress_bar`

A progress bar (determinate or indeterminate).

| Prop | Type | Description |
|------|------|-------------|
| `progress` | float | Current progress 0.0–1.0 (default `0.0`) |
| `indeterminate` | boolean | Show indeterminate spinner (default `false`) |
| `color` | color | Progress bar color |

```elixir
progress_bar progress: 0.7, color: :primary
progress_bar indeterminate: true
```

### `:activity_indicator`

A circular loading spinner.

| Prop | Type | Description |
|------|------|-------------|
| `size` | `:small` / `:large` | Spinner size (default `:small`) |
| `color` | color | Spinner color (default theme primary) |
| `animating` | boolean | Whether spinner is animating (default `true`) |

```elixir
activity_indicator size: :large, color: :primary
```

### `:toggle`

A boolean switch. Delivers `{:change, tag, value}` to `handle_event/3` where `value` is `true` or `false`.

| Prop | Type | Description |
|------|------|-------------|
| `value` | boolean | Current checked state |
| `on_change` | `{pid, tag}` | Fires when toggled. Delivers `{:change, tag, bool}`. |
| `text` | string | Label text displayed beside the toggle |
| `track_color` | color | Color when switch is on |
| `thumb_color` | color | Color of the draggable thumb |
| `accessibility_id` | string | Test identifier |

```elixir
toggle value: true, on_change: {self(), :notifications_toggled}, text: "Enable notifications"

def handle_event({:change, :notifications_toggled, enabled}, _params, socket) do
  {:noreply, Dala.Socket.assign(socket, :notifications_on, enabled)}
end
```

### `:slider`

A continuous value input. Delivers `{:change, tag, value}` to `handle_event/3` where `value` is a float.

| Prop | Type | Description |
|------|------|-------------|
| `value` | float | Current value (default `0.0`) |
| `min_value` | float | Minimum value (default `0.0`) |
| `max_value` | float | Maximum value (default `1.0`) |
| `on_change` | `{pid, tag}` | Fires as the user drags. Delivers `{:change, tag, float}`. |
| `color` | color | Track and thumb color |
| `accessibility_id` | string | Test identifier |

```elixir
slider value: 0.5, min_value: 0.0, max_value: 1.0, on_change: :volume_changed

def handle_event({:change, :volume_changed, value}, _params, socket) do
  {:noreply, Dala.Socket.assign(socket, :volume, value)}
end
```

### `:tab_bar`

A tab navigation bar.

| Prop | Type | Description |
|------|------|-------------|
| `tabs` | list of maps | Each map has `:id`, `:label`, and optional `:icon` |
| `active_tab` | string | The id of the currently selected tab |
| `on_tab_select` | `{pid, tag}` | Fired with selected tab id string |
| `accessibility_id` | string | Test identifier |

```elixir
tab_bar(
  tabs: [
    %{id: "home", label: "Home", icon: "home"},
    %{id: "settings", label: "Settings", icon: "settings"}
  ],
  active_tab: "home",
  on_tab_select: {self(), :tab_changed}
)
```

### `:refresh_control`

Pull-to-refresh control for scroll views.

| Prop | Type | Description |
|------|------|-------------|
| `on_refresh` | `{pid, tag}` | Fired when user pulls to refresh |
| `refreshing` | boolean | True while refresh is in progress |
| `tint_color` | color | Color of the refresh spinner |

```elixir
scroll padding: :space_md do
  refresh_control on_refresh: {self(), :refresh}, refreshing: @refreshing
  # content...
end
```

## Selection components

### `:checkbox`

A checkbox for selecting one or more items from a list. Maps to `Checkbox` on Compose and `Toggle` on SwiftUI.

| Prop | Type | Description |
|------|------|-------------|
| `value` | boolean | Current checked state |
| `on_change` | `{pid, tag}` | Fires when toggled. Delivers `{:change, tag, bool}`. |
| `label` | string | Label text displayed beside the checkbox |
| `color` | color | Checkbox tint color |
| `enabled` | boolean | Whether the checkbox is interactive (default `true`) |
| `accessibility_id` | string | Test identifier |

```elixir
checkbox value: true, on_change: {self(), :agree_toggled}, label: "I agree"

checkbox value: false, label: "Accept terms", color: :primary, enabled: false
```

### `:radio`

A radio button within a group. Only one radio in a group can be selected. Maps to `RadioButton` on Compose and `Toggle` with style on SwiftUI.

| Prop | Type | Description |
|------|------|-------------|
| `selected` | boolean | Whether this radio is selected |
| `on_select` | `{pid, tag}` | Fired when this radio is selected |
| `label` | string | Label text displayed beside the radio |
| `group` | string | Radio group name (radios in the same group are mutually exclusive) |
| `enabled` | boolean | Whether the radio is interactive (default `true`) |
| `color` | color | Radio tint color |
| `accessibility_id` | string | Test identifier |

```elixir
radio selected: true, on_select: {self(), :option_a}, label: "Option A", group: "choices"
```

### `:chip`

A compact Material Design chip. Maps to `FilterChip`, `InputChip`, etc. on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `label` | string | Chip text (required) |
| `variant` | `:assist` / `:filter` / `:input` / `:suggestion` | Chip style variant |
| `selected` | boolean | Selected state (for filter chips) |
| `on_tap` | `{pid, tag}` | Fired when chip is tapped |
| `icon` | string | Icon name displayed before the label |
| `on_remove` | `{pid, tag}` | Fired when remove icon is tapped (input chips) |
| `enabled` | boolean | Whether the chip is interactive (default `true`) |
| `accessibility_id` | string | Test identifier |

```elixir
chip label: "Filter", variant: :filter, selected: true, on_tap: {self(), :chip_tapped}
chip label: "Tag", variant: :input, on_remove: {self(), :tag_removed}
```

### `:carousel`

A horizontally scrolling carousel of items. Maps to `HorizontalPager` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `data` | enumerable | Items to render |
| `id` | atom | Carousel identifier |
| `on_page_change` | `{pid, tag}` | Fired with new page index on swipe |
| `loop` | boolean | Enable infinite looping (default `false`) |
| `peek` | float | Peek width for adjacent items |

```elixir
carousel id: :photo_carousel, data: @photos, on_page_change: {self(), :page_changed}
```

## Communication components

### `:snackbar`

A transient message bar with an optional action. Maps to `Snackbar` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `message` | string | The message text (required) |
| `action_label` | string | Label for the optional action button |
| `on_action` | `{pid, tag}` | Fired when the action button is tapped |
| `duration` | `:short` / `:long` | Display duration |
| `visible` | boolean | Whether the snackbar is shown (default `true`) |

```elixir
snackbar message: "Item deleted", action_label: "Undo", on_action: {self(), :undo}
```

### `:tooltip`

Shows a tooltip over its children. Maps to `Tooltip` on Compose and `help` modifier on SwiftUI.

| Prop | Type | Description |
|------|------|-------------|
| `text` | string | Tooltip text (required) |
| `position` | `:top` / `:bottom` / `:left` / `:right` | Tooltip position |

```elixir
tooltip text: "Save changes", position: :top do
  icon name: "save"
end
```

## Action components

### `:fab`

A Floating Action Button. Maps to `FloatingActionButton` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `icon` | string | Icon name (required) |
| `on_tap` | `{pid, tag}` | Fired when FAB is tapped |
| `text` | string | Optional label for extended FAB |
| `background` | color | Background color (default `:primary`) |
| `color` | color | Icon color (default `:on_primary`) |
| `corner_radius` | number / token | Corner radius |
| `elevation` | float | Shadow depth |
| `accessibility_id` | string | Test identifier |

```elixir
fab icon: "add", on_tap: {self(), :add_item}
fab icon: "edit", text: "Compose", on_tap: {self(), :compose}
```

### `:icon_button`

A clickable icon button. Maps to `IconButton` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `icon` | string | Icon name (required) |
| `on_tap` | `{pid, tag}` | Fired when button is tapped |
| `selected` | boolean | Toggle state for toggle icon buttons |
| `enabled` | boolean | Whether the button is interactive (default `true`) |
| `color` | color | Icon color |
| `background` | color | Background color |
| `accessibility_id` | string | Test identifier |

```elixir
icon_button icon: "favorite", on_tap: {self(), :favorite_tapped}
icon_button icon: "bookmark", selected: true, enabled: false
```

### `:segmented_button`

A segmented control with multiple segments. Maps to `SegmentedButton` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `segments` | list of maps | Each map has `:id`, `:label`, and optional `:icon` |
| `selected` | string | The id of the currently selected segment |
| `on_select` | `{pid, tag}` | Fired with selected segment id |
| `accessibility_id` | string | Test identifier |

```elixir
segmented_button(
  segments: [
    %{id: "day", label: "Day"},
    %{id: "week", label: "Week"},
    %{id: "month", label: "Month"}
  ],
  selected: "week",
  on_select: {self(), :range_changed}
)
```

## Navigation components

### `:app_bar`

A top app bar with title and action icons. Maps to `TopAppBar` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `title` | string | App bar title |
| `leading_icon` | string | Icon name for the leading navigation icon |
| `on_leading` | `{pid, tag}` | Fired when leading icon is tapped |
| `trailing_actions` | list of maps | Each map has `:icon` and `:on_tap` |
| `background` | color | Background color |
| `text_color` | color | Title and icon color |
| `accessibility_id` | string | Test identifier |

```elixir
app_bar(
  title: "My App",
  leading_icon: "back",
  on_leading: {self(), :back_pressed},
  trailing_actions: [%{icon: "search", on_tap: {self(), :search}}]
)
```

### `:nav_bar`

A bottom navigation bar. Maps to `NavigationBar` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `items` | list of maps | Each map has `:id`, `:label`, and `:icon` |
| `active` | string | Id of the currently active item |
| `on_select` | `{pid, tag}` | Fired with selected item id |
| `accessibility_id` | string | Test identifier |

```elixir
nav_bar(
  items: [
    %{id: "home", label: "Home", icon: "home"},
    %{id: "profile", label: "Profile", icon: "user"}
  ],
  active: "home",
  on_select: {self(), :tab_changed}
)
```

### `:nav_drawer`

A side navigation drawer. Maps to `ModalNavigationDrawer` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `visible` | boolean | Whether the drawer is shown |
| `on_dismiss` | `{pid, tag}` | Fired when the drawer is dismissed |
| `items` | list of maps | Each map has `:id`, `:label`, and `:icon` |
| `active` | string | Id of the currently active item |
| `on_select` | `{pid, tag}` | Fired with selected item id |
| `header` | string | Optional header text at the top |

```elixir
nav_drawer(
  visible: true,
  on_dismiss: {self(), :drawer_dismissed},
  items: [%{id: "home", label: "Home", icon: "home"}],
  active: "home",
  on_select: {self(), :nav_changed}
)
```

### `:nav_rail`

A side navigation rail (for tablets/desktop). Maps to `NavigationRail` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `items` | list of maps | Each map has `:id`, `:label`, and `:icon` |
| `active` | string | Id of the currently active item |
| `on_select` | `{pid, tag}` | Fired with selected item id |
| `accessibility_id` | string | Test identifier |

```elixir
nav_rail(
  items: [
    %{id: "home", label: "Home", icon: "home"},
    %{id: "settings", label: "Settings", icon: "settings"}
  ],
  active: "home",
  on_select: {self(), :rail_changed}
)
```

### `:menu`

A popup menu with selectable items. Maps to `DropdownMenu` on Compose.

| Prop | Type | Description |
|------|------|-------------|
| `items` | list of maps | Each map has `:label`, `:action` (atom), and optional `:icon` |
| `visible` | boolean | Whether the menu is shown |
| `on_dismiss` | `{pid, tag}` | Fired when the menu is dismissed |
| `on_select` | `{pid, tag}` | Fired with selected item's action atom |
| `accessibility_id` | string | Test identifier |

```elixir
menu(
  items: [%{label: "Edit", action: :edit}, %{label: "Delete", action: :delete}],
  visible: true,
  on_select: {self(), :menu_selected}
)
```

### `:date_picker`

A date selection dialog. Maps to `DatePicker` on Compose and `UIDatePicker` on SwiftUI.

| Prop | Type | Description |
|------|------|-------------|
| `visible` | boolean | Whether the picker is shown |
| `on_select` | `{pid, tag}` | Fired with selected date string (ISO 8601) |
| `on_dismiss` | `{pid, tag}` | Fired when the picker is dismissed |
| `selected_date` | string | Initial date in ISO 8601 format |
| `min_date` | string | Earliest selectable date |
| `max_date` | string | Latest selectable date |
| `title` | string | Optional title text |

```elixir
date_picker(
  visible: true,
  on_select: {self(), :date_picked},
  selected_date: "2025-01-15"
)
```

### `:time_picker`

A time selection dialog. Maps to `TimePicker` on Compose and `UIDatePicker` on SwiftUI.

| Prop | Type | Description |
|------|------|-------------|
| `visible` | boolean | Whether the picker is shown |
| `on_select` | `{pid, tag}` | Fired with selected time string (HH:MM) |
| `on_dismiss` | `{pid, tag}` | Fired when the picker is dismissed |
| `selected_time` | string | Initial time in HH:MM format |
| `title` | string | Optional title text |

```elixir
time_picker(
  visible: true,
  on_select: {self(), :time_picked},
  selected_time: "09:30"
)
```

### `:search_bar`

A search input bar with placeholder and callbacks. Maps to `SearchBar` on Compose and `UISearchBar` on SwiftUI.

| Prop | Type | Description |
|------|------|-------------|
| `placeholder` | string | Placeholder text when empty |
| `text` | string | Current search text |
| `on_change` | `{pid, tag}` | Fired on every text change |
| `on_submit` | `{pid, tag}` | Fired when search is submitted |
| `on_focus` | `{pid, tag}` | Fired when the bar gains focus |
| `active` | boolean | Whether the search bar is in active/expanded state |
| `on_tap` | `{pid, tag}` | Fired when the search bar is tapped |
| `accessibility_id` | string | Test identifier |

```elixir
search_bar(placeholder: "Search...", on_change: {self(), :search_changed}, on_submit: {self(), :search_submitted})
```

## Event handler conventions

In DSL style, event handlers are atoms that map directly to `handle_event/3` clauses:

```elixir
dala do
  screen name: :home do
    button "Save", on_tap: :save
  end
end

def handle_event(:save, _params, socket) do
  {:noreply, socket}
end
```

### Event routing

All events are delivered to the screen process via `handle_event/3`. Every `on_tap`, `on_change`, `on_select`, and similar handler sends its message directly to the screen process — regardless of how deeply the component is nested in the tree.

| Handler prop | Message delivered to `handle_event/3` |
|---|---|
| `on_tap: :tag` | `:tag` |
| `on_change: :tag` | `{:change, :tag, value}` |
| `on_select: :tag` (list) | `{:select, :tag, index}` |
| `on_submit: :tag` | `:tag` |
| `on_focus: :tag` | `:tag` |
| `on_blur: :tag` | `:tag` |
| `on_dismiss: :tag` | `:tag` |
| `on_action: :tag` | `:tag` |
| `on_leading: :tag` | `:tag` |
| `on_remove: :tag` | `:tag` |
| `on_page_change: :tag` | `{:page_change, index}` |

## Screen registration with `Dala.App.screens/1`

Register screen modules in your app's `navigation/1` callback using `screens/1`. This validates at compile time that modules are valid `Dala.Screen` modules:

```elixir
defmodule MyApp do
  use Dala.App

  def navigation(_platform) do
    screens([MyApp.HomeScreen, MyApp.SettingsScreen])
    stack(:home, root: MyApp.HomeScreen)
  end
end
```

See [Navigation](navigation.md) for full details.