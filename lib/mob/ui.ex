defmodule Mob.UI do
  @moduledoc """
  UI component constructors for the Mob framework.

  Each function returns a node map compatible with `Mob.Renderer`. These can
  be used directly, via the `~MOB` sigil, or mixed freely — they produce the
  same map format.

      # Native map literal
      %{type: :text, props: %{text: "Hello"}, children: []}

      # Component function (keyword list or map)
      Mob.UI.text(text: "Hello")

      # Sigil (import Mob.Sigil or use Mob.Screen)
      ~MOB(<Text text="Hello" />)

  All three forms produce identical output and are accepted by `Mob.Renderer`.
  """

  @text_props [:text, :text_color, :text_size]

  @doc """
  Returns a `:text` leaf node.

  ## Props

    * `:text` — the string to display (required)
    * `:text_color` — color value passed to `set_text_color/2` in the NIF
    * `:text_size` — font size in sp passed to `set_text_size/2` in the NIF

  ## Examples

      Mob.UI.text(text: "Hello")
      #=> %{type: :text, props: %{text: "Hello"}, children: []}

      Mob.UI.text(text: "Hello", text_color: "#ffffff", text_size: 18)
      #=> %{type: :text, props: %{text: "Hello", text_color: "#ffffff", text_size: 18}, children: []}
  """
  @spec text(keyword() | map()) :: map()
  def text(props) when is_list(props), do: text(Map.new(props))

  def text(%{} = props) do
    %{
      type: :text,
      props: Map.take(props, @text_props),
      children: []
    }
  end

  @doc """
  Returns a `:webview` component node. Renders a native web view inline.

  The JS bridge is injected automatically — the page can call `window.mob.send(data)`
  to deliver messages to `handle_info({:webview, :message, data}, socket)`, and
  Elixir can push to JS via `Mob.WebView.post_message/2`.

  Props:
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

  Call `Mob.Camera.start_preview/2` before mounting this component, and
  `Mob.Camera.stop_preview/1` when done.

  Props:
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

  `module` must implement the `Mob.Component` behaviour and be registered
  on the native side via `MobNativeViewRegistry`. The `:id` must be unique
  per screen — a duplicate raises at render time.

  All other props are passed to `mount/2` and `update/2` on the component.

  ## Example

      Mob.UI.native_view(MyApp.ChartComponent, id: :revenue_chart, data: @points)

  """
  @spec native_view(module(), keyword() | map()) :: map()
  def native_view(module, props \\ [])
  def native_view(module, props) when is_list(props), do: native_view(module, Map.new(props))

  def native_view(module, %{} = props) when is_atom(module) do
    %{type: :native_view, props: Map.put(props, :module, module), children: []}
  end

  @doc """
  Returns an `:image` leaf node. Displays an image from a URL or local asset.

  Props:
    * `:src` — URL or local asset name (required)
    * `:resize_mode` — `:cover` (default), `:contain`, `:stretch`, `:repeat`
    * `:width`, `:height` — dimensions in dp/pts; omit to auto-size
    * `:corner_radius` — optional rounded corners
  """
  @spec image(keyword() | map()) :: map()
  def image(props \\ [])
  def image(props) when is_list(props), do: image(Map.new(props))

  def image(%{} = props) do
    %{
      type: :image,
      props: Map.take(props, [:src, :resize_mode, :width, :height, :corner_radius]),
      children: []
    }
  end

  @doc """
  Returns a `:switch` leaf node. A boolean toggle switch.

  Props:
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

  Props:
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

  Props:
    * `:visible` — boolean, controls whether modal is shown (default: false)
    * `:on_dismiss` — `{pid, tag}` tuple; fired when user dismisses modal
    * `:presentation_style` — `:full_screen` (default) or `:page_sheet`
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

  Props:
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
  Returns a `:button` leaf node. A simple platform button.

  Props:
    * `:title` — button label (required)
    * `:on_tap` — `{pid, tag}` tuple; fired when button is pressed
    * `:color` — button color (use `:background` for theme-aware coloring)
    * `:disabled` — boolean, disables the button (default: false)
  """
  @spec button(keyword() | map()) :: map()
  def button(props \\ [])
  def button(props) when is_list(props), do: button(Map.new(props))

  def button(%{} = props) do
    %{
      type: :button,
      props: Map.take(props, [:title, :on_tap, :color, :disabled]),
      children: []
    }
  end

  @doc """
  Returns a `:scroll` container node. A scrollable view (ScrollView equivalent).

  Props:
    * `:horizontal` — boolean, enables horizontal scrolling (default: false)
    * `:on_end_reached` — `{pid, tag}` tuple; fired when scroll reaches bottom/end
    * `:on_scroll` — `{pid, tag}` tuple; fired during scrolling with scroll position
  """
  @spec scroll(keyword() | map(), list()) :: map()
  def scroll(props \\ [], children \\ [])
  def scroll(props, children) when is_list(props), do: scroll(Map.new(props), children)

  def scroll(%{} = props, children) when is_list(children) do
    %{
      type: :scroll,
      props: Map.take(props, [:horizontal, :on_end_reached, :on_scroll]),
      children: children
    }
  end

  @doc """
  Returns a `:pressable` container node. A pressable wrapper (Pressable equivalent).

  Props:
    * `:on_press` — `{pid, tag}` tuple; fired when pressed
    * `:on_long_press` — `{pid, tag}` tuple; fired on long press
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
  Returns a `:safe_area` container node. Applies safe area insets (SafeAreaView equivalent).

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

  Props:
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

  Props:
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

  Leverages `Mob.List` for rendering. Requires an `:id` prop to identify the list
  for selection events and custom renderers.

  Props:
    * `:data` — enumerable of items to render (mapped to `:items`)
    * `:id` — atom identifier for the list (required for selection events)
    * `:on_end_reached` — `{pid, tag}` tuple; fired when list reaches end
    * `:scroll` — boolean, enables scrolling (default: true)

  For custom item rendering, register a renderer via `Mob.List.put_renderer/3` in `mount/3`.

  ## Examples

      Mob.UI.list(id: :my_list, data: assigns.items)

      # With custom renderer in mount/3:
      # Mob.List.put_renderer(socket, :my_list, fn item -> ... end)
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
end
