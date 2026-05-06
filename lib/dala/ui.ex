defmodule Dala.UI do
  @moduledoc """
  UI component constructors for the Dala framework.

  Each function returns a node map compatible with `Dala.Renderer`. These can
  be used directly, via the `~dala` sigil, or mixed freely — they produce the
  same map format.

      # Native map literal
      %{type: :text, props: %{text: "Hello"}, children: []}

      # Component function (keyword list or map)
      Dala.UI.text(text: "Hello")

      # Sigil (import Dala.Sigil or use Dala.Screen)
      ~dala(<Text text="Hello" />)

  All three forms produce identical output and are accepted by `Dala.Renderer`.
  """

  # ── Shared prop sets ──────────────────────────────────────────────────────
  # These are used by Map.take to filter props, keeping the serialised tree
  # clean and avoiding typos silently swallowed.

  @typography_props [
    :text,
    :text_color,
    :text_size,
    :font_weight,
    :font_family,
    :text_align,
    :italic,
    :line_height,
    :letter_spacing
  ]

  @layout_props [
    :padding,
    :padding_top,
    :padding_right,
    :padding_bottom,
    :padding_left,
    :gap,
    :background,
    :border_color,
    :border_width,
    :corner_radius,
    :fill_width,
    :width,
    :height
  ]

  @gesture_props [
    :on_tap,
    :on_long_press,
    :on_double_tap,
    :on_swipe,
    :on_swipe_left,
    :on_swipe_right,
    :on_swipe_up,
    :on_swipe_down
  ]

  @accessibility_props [:accessibility_id]

  # ── Layout containers ─────────────────────────────────────────────────────

  @doc """
  Returns a `:column` container node. Children are laid out vertically (VStack).

  ## Props

    * `:gap` — spacing between children (accepts spacing tokens like `:space_md`)
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:background` — background color (accepts color tokens)
    * `:border_color`, `:border_width` — optional border
    * `:corner_radius` — rounded corners
    * `:fill_width` — boolean, stretch to fill parent width
    * `:on_tap`, `:on_long_press`, `:on_double_tap`, `:on_swipe*` — gesture handlers
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.column([padding: :space_md, gap: :space_sm], [
        Dala.UI.text(text: "Title"),
        Dala.UI.text(text: "Subtitle")
      ])
  """
  @spec column(keyword() | map(), list()) :: map()
  def column(props \\ [], children \\ [])
  def column(props, children) when is_list(props), do: column(Map.new(props), children)

  def column(%{} = props, children) when is_list(children) do
    allowed = @layout_props ++ @gesture_props ++ @accessibility_props

    %{
      type: :column,
      props: Map.take(props, allowed),
      children: children
    }
  end

  @doc """
  Returns a `:row` container node. Children are laid out horizontally (HStack).

  Same props as `column/2`.
  """
  @spec row(keyword() | map(), list()) :: map()
  def row(props \\ [], children \\ [])
  def row(props, children) when is_list(props), do: row(Map.new(props), children)

  def row(%{} = props, children) when is_list(children) do
    allowed = @layout_props ++ @gesture_props ++ @accessibility_props

    %{
      type: :row,
      props: Map.take(props, allowed),
      children: children
    }
  end

  @doc """
  Returns a `:box` container node. Children are stacked on top of each other (ZStack).

  Same props as `column/2`. Useful for overlays, badges, and absolute positioning.
  """
  @spec box(keyword() | map(), list()) :: map()
  def box(props \\ [], children \\ [])
  def box(props, children) when is_list(props), do: box(Map.new(props), children)

  def box(%{} = props, children) when is_list(children) do
    allowed = @layout_props ++ @gesture_props ++ @accessibility_props

    %{
      type: :box,
      props: Map.take(props, allowed),
      children: children
    }
  end

  # ── Leaf nodes ────────────────────────────────────────────────────────────

  @doc """
  Returns a `:text` leaf node.

  ## Props

    * `:text` — the string to display (required)
    * `:text_color` — color value (accepts color tokens like `:on_surface`)
    * `:text_size` — font size (accepts size tokens like `:xl` or numeric sp)
    * `:font_weight` — `"regular"`, `"medium"`, `"semibold"`, `"bold"`, `"light"`, `"thin"`
    * `:font_family` — custom font family name (nil = system font)
    * `:text_align` — `:left`, `:center`, `:right`
    * `:italic` — boolean
    * `:line_height` — multiplier (e.g. `1.5` for 150% line height)
    * `:letter_spacing` — extra spacing in pt
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:background` — background color
    * `:corner_radius` — rounded corners
    * `:fill_width` — boolean, stretch to fill parent width
    * `:on_tap`, `:on_long_press`, `:on_double_tap` — gesture handlers
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.text(text: "Hello")
      Dala.UI.text(text: "Title", text_size: :xl, font_weight: "bold", text_color: :on_surface)
  """
  @spec text(keyword() | map()) :: map()
  def text(props) when is_list(props), do: text(Map.new(props))

  def text(%{} = props) do
    allowed = @typography_props ++ @layout_props ++ @gesture_props ++ @accessibility_props

    %{
      type: :text,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @doc """
  Returns a `:button` leaf node.

  ## Props

    * `:text` — button label (required). Also accepts `:title` for backward compatibility.
    * `:on_tap` — `{pid, tag}` tuple; fired when button is pressed
    * `:disabled` — boolean, disables the button (default: false)
    * `:text_color` — label color (accepts color tokens)
    * `:text_size` — font size
    * `:font_weight` — `"regular"`, `"medium"`, `"semibold"`, `"bold"`, `"light"`, `"thin"`
    * `:background` — button background color (accepts color tokens)
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:corner_radius` — rounded corners
    * `:fill_width` — boolean, stretch to fill parent width (default: true from component defaults)
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.button(text: "Submit", on_tap: {self(), :submit})
      Dala.UI.button(title: "OK", on_tap: {self(), :ok}, background: :primary)
  """
  @spec button(keyword() | map()) :: map()
  def button(props \\ [])
  def button(props) when is_list(props), do: button(Map.new(props))

  def button(%{} = props) do
    # Backward compat: :title maps to :text (native side uses node.text)
    props = Map.put_new(props, :text, props[:title])

    allowed =
      [:text, :on_tap, :disabled] ++
        [:text_color, :text_size, :font_weight] ++
        [:background, :padding, :padding_top, :padding_right, :padding_bottom, :padding_left] ++
        [:corner_radius, :fill_width, :accessibility_id]

    %{
      type: :button,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @doc """
  Returns an `:icon` leaf node. Displays a platform-native icon.

  Logical icon names are resolved to SF Symbols on iOS and Material Symbols on
  Android. Unknown names pass through verbatim (power users can use raw SF Symbol
  identifiers like `"globe.americas.fill"`).

  ## Props

    * `:name` — logical icon name or raw identifier (required)
    * `:text_size` — glyph size in sp
    * `:text_color` — glyph tint color (accepts color tokens)
    * `:padding`, `:background` — layout props
    * `:on_tap`, `:on_long_press` — gesture handlers
    * `:accessibility_id` — test identifier (also used as accessibility label)

  ## Logical icon names

  `settings`, `back`, `forward`, `close`, `add`, `remove`, `edit`, `check`,
  `chevron_right`, `chevron_left`, `chevron_up`, `chevron_down`, `info`,
  `warning`, `error`, `search`, `trash`, `share`, `more`, `menu`, `refresh`,
  `favorite`, `favorite_filled`, `star`, `star_filled`, `user`, `home`

  ## Examples

      Dala.UI.icon(name: "settings", text_size: 24, text_color: :on_surface)
      Dala.UI.icon(name: "chevron_right", on_tap: {self(), :navigate})
  """
  @spec icon(keyword() | map()) :: map()
  def icon(props \\ [])
  def icon(props) when is_list(props), do: icon(Map.new(props))

  def icon(%{} = props) do
    allowed =
      [:name, :text_size, :text_color] ++
        [:padding, :background] ++
        [:on_tap, :on_long_press] ++
        @accessibility_props

    %{
      type: :icon,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @doc """
  Returns a `:divider` leaf node. A horizontal or vertical divider line.

  ## Props

    * `:thickness` — line thickness in pt (default: 1.0)
    * `:color` — divider color (accepts color tokens, default: `:border`)
    * `:padding` — padding around the divider

  ## Examples

      Dala.UI.divider()
      Dala.UI.divider(thickness: 2, color: :primary)
  """
  @spec divider(keyword() | map()) :: map()
  def divider(props \\ [])
  def divider(props) when is_list(props), do: divider(Map.new(props))

  def divider(%{} = props) do
    %{
      type: :divider,
      props: Map.take(props, [:thickness, :color, :padding]),
      children: []
    }
  end

  @doc """
  Returns a `:spacer` leaf node. Flexible or fixed space.

  ## Props

    * `:size` — fixed size in pt (omit for flexible spacer that fills available space)

  ## Examples

      Dala.UI.spacer()          # flexible — fills available space
      Dala.UI.spacer(size: 20)  # fixed 20pt gap
  """
  @spec spacer(keyword() | map()) :: map()
  def spacer(props \\ [])
  def spacer(props) when is_list(props), do: spacer(Map.new(props))

  def spacer(%{} = props) do
    %{
      type: :spacer,
      props: Map.take(props, [:size]),
      children: []
    }
  end

  @doc """
  Returns a `:text_field` leaf node. A single-line text input.

  ## Props

    * `:text` — initial/current text value
    * `:placeholder` — placeholder text when empty
    * `:on_change` — `{pid, tag}` tuple; fired on every text change with new value
    * `:on_focus` — `{pid, tag}` tuple; fired when field gains focus
    * `:on_blur` — `{pid, tag}` tuple; fired when field loses focus
    * `:on_submit` — `{pid, tag}` tuple; fired when return key is pressed
    * `:on_compose` — `{pid, tag}` tuple; IME composition events (CJK, etc.)
    * `:keyboard_type` — `:default`, `:number`, `:decimal`, `:email`, `:phone`, `:url`
    * `:return_key` — `:done`, `:next`, `:go`, `:search`, `:send`
    * `:text_color`, `:text_size` — typography
    * `:background`, `:padding`, `:corner_radius` — layout
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.text_field(placeholder: "Enter name", on_change: {self(), :name_changed})
      Dala.UI.text_field(keyboard_type: :email, return_key: :next, on_submit: {self(), :next_field})
  """
  @spec text_field(keyword() | map()) :: map()
  def text_field(props \\ [])
  def text_field(props) when is_list(props), do: text_field(Map.new(props))

  def text_field(%{} = props) do
    allowed =
      [:text, :placeholder, :on_change, :on_focus, :on_blur, :on_submit, :on_compose] ++
        [:keyboard_type, :return_key] ++
        [:text_color, :text_size] ++
        [:background, :padding, :corner_radius] ++
        @accessibility_props

    %{
      type: :text_field,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @doc """
  Returns a `:toggle` leaf node. A boolean toggle switch.

  ## Props

    * `:value` — boolean, on/off state (default: false)
    * `:on_change` — `{pid, tag}` tuple; fired with new boolean value on toggle
    * `:text` — optional label text displayed beside the switch
    * `:track_color` — color when switch is on
    * `:thumb_color` — color of the draggable thumb
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.toggle(value: true, on_change: {self(), :notifications_toggled}, text: "Notifications")
  """
  @spec toggle(keyword() | map()) :: map()
  def toggle(props \\ [])
  def toggle(props) when is_list(props), do: toggle(Map.new(props))

  def toggle(%{} = props) do
    %{
      type: :toggle,
      props:
        Map.take(props, [:value, :on_change, :text, :track_color, :thumb_color, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:slider` leaf node. A continuous range slider.

  ## Props

    * `:value` — current value (default: 0.0)
    * `:min_value` — minimum value (default: 0.0)
    * `:max_value` — maximum value (default: 1.0)
    * `:on_change` — `{pid, tag}` tuple; fired with new float value on drag
    * `:color` — slider tint color
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.slider(value: 0.5, min_value: 0, max_value: 100, on_change: {self(), :volume_changed})
  """
  @spec slider(keyword() | map()) :: map()
  def slider(props \\ [])
  def slider(props) when is_list(props), do: slider(Map.new(props))

  def slider(%{} = props) do
    %{
      type: :slider,
      props:
        Map.take(props, [:value, :min_value, :max_value, :on_change, :color, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:tab_bar` container node. A tab navigation bar.

  ## Props

    * `:tabs` — list of tab definitions, each a map with `:id`, `:label`, and optional `:icon`
    * `:active_tab` — the id of the currently selected tab
    * `:on_tab_select` — `{pid, tag}` tuple; fired with selected tab id string
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.tab_bar(
        tabs: [
          %{id: "home", label: "Home", icon: "home"},
          %{id: "settings", label: "Settings", icon: "settings"}
        ],
        active_tab: "home",
        on_tab_select: {self(), :tab_changed}
      )
  """
  @spec tab_bar(keyword() | map()) :: map()
  def tab_bar(props \\ [])
  def tab_bar(props) when is_list(props), do: tab_bar(Map.new(props))

  def tab_bar(%{} = props) do
    %{
      type: :tab_bar,
      props: Map.take(props, [:tabs, :active_tab, :on_tab_select, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:video` leaf node. An inline video player.

  ## Props

    * `:src` — video URL (required)
    * `:autoplay` — boolean, start playing immediately (default: false)
    * `:loop` — boolean, loop playback (default: false)
    * `:controls` — boolean, show playback controls (default: true)
    * `:width`, `:height` — dimensions in dp/pts; omit to fill parent

  ## Examples

      Dala.UI.video(src: "https://example.com/clip.mp4", autoplay: true, loop: true)
  """
  @spec video(keyword() | map()) :: map()
  def video(props \\ [])
  def video(props) when is_list(props), do: video(Map.new(props))

  def video(%{} = props) do
    %{
      type: :video,
      props: Map.take(props, [:src, :autoplay, :loop, :controls, :width, :height]),
      children: []
    }
  end

  # ── Existing components (expanded prop support) ───────────────────────────

  @doc """
  Returns an `:image` leaf node. Displays an image from a URL or local asset.

  ## Props

    * `:src` — URL or local asset name (required)
    * `:resize_mode` — `:cover` (default), `:contain`, `:stretch`, `:repeat`
    * `:width`, `:height` — dimensions in dp/pts; omit to auto-size
    * `:corner_radius` — optional rounded corners
    * `:placeholder_color` — color shown while loading
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.UI.image(src: "https://example.com/photo.jpg", resize_mode: :cover, corner_radius: 12)
  """
  @spec image(keyword() | map()) :: map()
  def image(props \\ [])
  def image(props) when is_list(props), do: image(Map.new(props))

  def image(%{} = props) do
    %{
      type: :image,
      props:
        Map.take(props, [
          :src,
          :resize_mode,
          :width,
          :height,
          :corner_radius,
          :placeholder_color,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:switch` leaf node. A boolean toggle switch.

  Prefer `toggle/1` for new code — it uses `:on_change` consistent with other
  value widgets. This function is kept for backward compatibility.

  ## Props

    * `:value` — boolean, on/off state (default: false)
    * `:on_toggle` — `{pid, tag}` tuple; fires `{:toggle, tag, new_value}` to handler
    * `:track_color` — color when switch is on
    * `:thumb_color` — color of the draggable thumb
  """
  @spec switch(keyword() | map()) :: map()
  def switch(props \\ [])
  def switch(props) when is_list(props), do: switch(Map.new(props))

  def switch(%{} = props) do
    %{
      type: :switch,
      props: Map.take(props, [:value, :on_toggle, :track_color, :thumb_color]),
      children: []
    }
  end

  @doc """
  Returns an `:activity_indicator` leaf node. Displays a circular loading spinner.

  ## Props

    * `:size` — `:small` or `:large` (default: `:small`)
    * `:color` — spinner color (default: theme primary)
    * `:animating` — whether spinner is animating (default: true)
  """
  @spec activity_indicator(keyword() | map()) :: map()
  def activity_indicator(props \\ [])
  def activity_indicator(props) when is_list(props), do: activity_indicator(Map.new(props))

  def activity_indicator(%{} = props) do
    %{
      type: :activity_indicator,
      props: Map.take(props, [:size, :color, :animating]),
      children: []
    }
  end

  @doc """
  Returns a `:modal` container node. Presents content above the enclosing view.

  ## Props

    * `:visible` — boolean, controls whether modal is shown (default: false)
    * `:on_dismiss` — `{pid, tag}` tuple; fired when user dismisses modal
    * `:presentation_style` — `:full_screen` (default) or `:page_sheet`

  ## Examples

      Dala.UI.modal([visible: true, on_dismiss: {self(), :dismissed}], [
        Dala.UI.text(text: "Modal content")
      ])
  """
  @spec modal(keyword() | map(), list()) :: map()
  def modal(props \\ [], children \\ [])
  def modal(props, children) when is_list(props), do: modal(Map.new(props), children)

  def modal(%{} = props, children) when is_list(children) do
    %{
      type: :modal,
      props: Map.take(props, [:visible, :on_dismiss, :presentation_style]),
      children: children
    }
  end

  @doc """
  Returns a `:refresh_control` leaf node. Adds pull-to-refresh to ScrollView.

  Attach as a child of `:scroll` node. The scroll node handles the refresh gesture.

  ## Props

    * `:on_refresh` — `{pid, tag}` tuple; fired when user pulls to refresh
    * `:refreshing` — boolean, true while refresh is in progress
    * `:tint_color` — color of the refresh spinner
  """
  @spec refresh_control(keyword() | map()) :: map()
  def refresh_control(props \\ [])
  def refresh_control(props) when is_list(props), do: refresh_control(Map.new(props))

  def refresh_control(%{} = props) do
    %{
      type: :refresh_control,
      props: Map.take(props, [:on_refresh, :refreshing, :tint_color]),
      children: []
    }
  end

  @doc """
  Returns a `:scroll` container node. A scrollable view (ScrollView equivalent).

  ## Props

    * `:horizontal` — boolean, enables horizontal scrolling (default: false)
    * `:show_indicator` — boolean, show scroll indicator (default: true)
    * `:on_end_reached` — `{pid, tag}` tuple; fired when scroll reaches bottom/end
    * `:on_scroll` — `{pid, tag}` tuple; fired during scrolling with scroll position
    * `:padding`, `:background` — layout props

  ## Examples

      Dala.UI.scroll([padding: :space_md], [
        Dala.UI.text(text: "Long content...")
      ])
  """
  @spec scroll(keyword() | map(), list()) :: map()
  def scroll(props \\ [], children \\ [])
  def scroll(props, children) when is_list(props), do: scroll(Map.new(props), children)

  def scroll(%{} = props, children) when is_list(children) do
    allowed =
      [:horizontal, :show_indicator, :on_end_reached, :on_scroll] ++
        [:padding, :background]

    %{
      type: :scroll,
      props: Map.take(props, allowed),
      children: children
    }
  end

  @doc """
  Returns a `:pressable` container node. A pressable wrapper.

  ## Props

    * `:on_press` — `{pid, tag}` tuple; fired when pressed
    * `:on_long_press` — `{pid, tag}` tuple; fired on long press

  ## Examples

      Dala.UI.pressable([on_press: {self(), :card_tapped}], [
        Dala.UI.text(text: "Tap me")
      ])
  """
  @spec pressable(keyword() | map(), list()) :: map()
  def pressable(props \\ [], children \\ [])
  def pressable(props, children) when is_list(props), do: pressable(Map.new(props), children)

  def pressable(%{} = props, children) when is_list(children) do
    %{
      type: :pressable,
      props: Map.take(props, [:on_press, :on_long_press]),
      children: children
    }
  end

  @doc """
  Returns a `:safe_area` container node. Applies safe area insets.

  Renders children within the safe area boundaries (avoiding notches, status bar, etc.).
  """
  @spec safe_area(list()) :: map()
  def safe_area(children \\ [])

  def safe_area(children) when is_list(children) do
    %{
      type: :safe_area,
      props: %{},
      children: children
    }
  end

  @doc """
  Returns a `:status_bar` leaf node. Controls the status bar appearance.

  ## Props

    * `:bar_style` — `:default` (dark text) or `:light_content` (light text)
    * `:hidden` — boolean, hides the status bar (default: false)
  """
  @spec status_bar(keyword() | map()) :: map()
  def status_bar(props \\ [])
  def status_bar(props) when is_list(props), do: status_bar(Map.new(props))

  def status_bar(%{} = props) do
    %{
      type: :status_bar,
      props: Map.take(props, [:bar_style, :hidden]),
      children: []
    }
  end

  @doc """
  Returns a `:progress_bar` leaf node. Displays a progress bar.

  ## Props

    * `:progress` — float 0.0 to 1.0, current progress (default: 0.0)
    * `:indeterminate` — boolean, shows indeterminate spinner (default: false)
    * `:color` — progress bar color
  """
  @spec progress_bar(keyword() | map()) :: map()
  def progress_bar(props \\ [])
  def progress_bar(props) when is_list(props), do: progress_bar(Map.new(props))

  def progress_bar(%{} = props) do
    %{
      type: :progress_bar,
      props: Map.take(props, [:progress, :indeterminate, :color]),
      children: []
    }
  end

  @doc """
  Returns a `:list` node. A data-driven list (FlatList equivalent).

  Leverages `Dala.List` for rendering. Requires an `:id` prop to identify the list
  for selection events and custom renderers.

  ## Props

    * `:data` — enumerable of items to render (mapped to `:items`)
    * `:id` — atom identifier for the list (required for selection events)
    * `:on_end_reached` — `{pid, tag}` tuple; fired when list reaches end
    * `:scroll` — boolean, enables scrolling (default: true)

  For custom item rendering, register a renderer via `Dala.List.put_renderer/3` in `mount/3`.

  ## Examples

      Dala.UI.list(id: :my_list, data: assigns.items)

      # With custom renderer in mount/3:
      # Dala.List.put_renderer(socket, :my_list, fn item -> ... end)
  """
  @spec list(keyword() | map()) :: map()
  def list(props \\ [])
  def list(props) when is_list(props), do: list(Map.new(props))

  def list(%{} = props) do
    items = props[:data] || []
    list_props = props |> Map.drop([:data]) |> Map.put(:items, items)

    %{
      type: :list,
      props: Map.take(list_props, [:id, :items, :on_end_reached, :scroll]),
      children: []
    }
  end

  @doc """
  Returns a `:webview` component node. Renders a native web view inline.

  The JS bridge is injected automatically — the page can call `window.dala.send(data)`
  to deliver messages to `handle_info({:webview, :message, data}, socket)`, and
  Elixir can push to JS via `Dala.WebView.post_message/2`.

  ## Props

    * `:url` — URL to load (required)
    * `:allow` — list of URL prefixes that navigation is permitted to (default: allow all).
      Blocked attempts arrive as `{:webview, :blocked, url}` in `handle_info`.
    * `:show_url` — show a native URL label above the WebView (default: false)
    * `:title` — static title label above the WebView; overrides `:show_url`
    * `:width`, `:height` — dimensions in dp/pts; omit to fill parent
  """
  @spec webview(keyword() | map()) :: map()
  def webview(props \\ [])
  def webview(props) when is_list(props), do: webview(Map.new(props))

  def webview(%{} = props) do
    allow_str = (props[:allow] || []) |> Enum.join(",")

    node_props =
      %{url: props[:url] || "", allow: allow_str, show_url: props[:show_url] || false}
      |> then(fn p -> if props[:title], do: Map.put(p, :title, props[:title]), else: p end)
      |> then(fn p -> if props[:width], do: Map.put(p, :width, props[:width]), else: p end)
      |> then(fn p -> if props[:height], do: Map.put(p, :height, props[:height]), else: p end)

    %{type: :web_view, props: node_props, children: []}
  end

  @doc """
  Returns a `:camera_preview` component node. Renders a live camera feed inline.

  Call `Dala.Camera.start_preview/2` before mounting this component, and
  `Dala.Camera.stop_preview/1` when done.

  ## Props

    * `:facing` — `:back` (default) or `:front`
    * `:width`, `:height` — dimensions in dp/pts; omit to fill parent
  """
  @spec camera_preview(keyword() | map()) :: map()
  def camera_preview(props \\ [])
  def camera_preview(props) when is_list(props), do: camera_preview(Map.new(props))

  def camera_preview(%{} = props) do
    %{
      type: :camera_preview,
      props: Map.take(props, [:facing, :width, :height]),
      children: []
    }
  end

  @doc """
  Returns a `:native_view` node that renders a platform-native component.

  `module` must implement the `Dala.Component` behaviour and be registered
  on the native side via `dalaNativeViewRegistry`. The `:id` must be unique
  per screen — a duplicate raises at render time.

  All other props are passed to `mount/2` and `update/2` on the component.

  ## Example

      Dala.UI.native_view(MyApp.ChartComponent, id: :revenue_chart, data: @points)

  """
  @spec native_view(module(), keyword() | map()) :: map()
  def native_view(module, props \\ [])
  def native_view(module, props) when is_list(props), do: native_view(module, Map.new(props))

  def native_view(module, %{} = props) when is_atom(module) do
    %{type: :native_view, props: Map.put(props, :module, module), children: []}
  end
end
