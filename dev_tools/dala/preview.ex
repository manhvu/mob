defmodule Dala.Preview do
  @moduledoc """
  Interactive HTML preview for Dala UI components.

  This module generates static HTML with CSS that mimics Dala's styling,
  allowing you to preview UI trees in a browser without a simulator.

  ## Features

  - Renders all major Dala UI components (column, row, text, button, etc.)
  - Interactive simulation (tap, drag, swipe handlers shown visually)
  - Event logging panel to see interactions
  - Component tree inspector (toggleable with Alpine.js)
  - No LiveView dependency - pure static HTML

  ## Usage

      # In IEx (dev environment)
      Dala.Preview.preview(MyApp.HomeScreen)
      Dala.Preview.preview_to_file(MyApp.HomeScreen, "preview.html")
      Dala.Preview.preview_and_open(MyApp.HomeScreen)

      # With a UI tree directly
      ui_tree = %{type: :column, props: %{padding: :md}, children: [...]}
      Dala.Preview.preview(ui_tree)

  ## Options

    * `:show_tree` - Show component tree inspector (default: true)
    * `:title` - Custom title for the preview page
  """

  @doc """
  Generate HTML preview for a module or UI tree.
  """
  def preview(source, opts \\ []) do
    ui_tree = resolve_ui_tree(source)
    generate_html(ui_tree, opts)
  end

  @doc """
  Generate HTML preview and save to file.
  """
  def preview_to_file(source, filename \\ "dala_preview.html", opts \\ []) do
    ui_tree = resolve_ui_tree(source)
    html = generate_html(ui_tree, opts)
    path = Path.join(File.cwd!(), filename)
    File.write!(path, html)
    path
  end

  @doc """
  Generate HTML preview and open in browser.
  """
  def preview_and_open(source, opts \\ []) do
    path = preview_to_file(source, "dala_preview.html", opts)
    open_in_browser(path)
    :ok
  end

  @doc """
  Open a file in the default browser.
  """
  def open_in_browser(path) do
    path
    |> Path.expand()
    |> System.cmd("open", [])
  end

  defp resolve_ui_tree(module) when is_atom(module) do
    fetch_screen_tree(module)
  end

  defp resolve_ui_tree(ui_tree) when is_map(ui_tree) or is_list(ui_tree) do
    ui_tree
  end

  defp fetch_screen_tree(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :render, 1) do
      module.render(%{})
    else
      default_preview()
    end
  end

  defp default_preview do
    %{
      type: :column,
      props: %{padding: :md},
      children: [
        %{type: :text, props: %{text: "Preview not available"}, children: []}
      ]
    }
  end

  defp generate_html(ui_tree, opts) do
    show_tree = Keyword.get(opts, :show_tree, true)
    title = Keyword.get(opts, :title, "Dala UI Preview - Interactive Simulation Dev Tool")

    tree_html = render_ui_tree(ui_tree)
    tree_inspector = if show_tree, do: generate_tree_inspector(ui_tree), else: ""

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
      <title>#{title}</title>
      <script src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
      <style>
        #{base_css()}
      </style>
    </head>
    <body>
      <div class="dala-preview-container">
        <div class="preview-header">
          <h2>Dala Preview - Interactive Simulation</h2>
        </div>
        <div class="preview-content">
          #{tree_html}
        </div>
        #{tree_inspector}
        <div class="event-log">
          <h3>Event Log</h3>
          <div id="log-entries">Interact with the preview to see events here.</div>
        </div>
      </div>
      <script>
        #{interactive_js()}
      </script>
    </body>
    </html>
    """
  end

  defp render_ui_tree(tree) when is_list(tree) do
    Enum.map(tree, &render_ui_tree/1) |> Enum.join("\n")
  end

  defp render_ui_tree(%{type: type, props: props, children: children}) do
    render_component(type, props, children)
  end

  defp render_ui_tree(%{"type" => type, "props" => props, "children" => children}) do
    render_component(type, props, children)
  end

  defp render_ui_tree(_), do: ""

  defp render_component(:column, props, children) do
    style = build_style(props)
    """
    <div class="dala-column" style="#{style}">
      #{render_children(children)}
    </div>
    """
  end

  defp render_component(:row, props, children) do
    style = build_style(props)
    """
    <div class="dala-row" style="#{style}">
      #{render_children(children)}
    </div>
    """
  end

  defp render_component(:text, props, _children) do
    text = html_escape(props[:text] || "")
    style = build_text_style(props)
    ~s(<div class="dala-text" style="#{style}">#{text}</div>)
  end

  defp render_component(:button, props, _children) do
    text = html_escape(props[:text] || "Button")
    on_tap = props[:on_tap]
    data_attr = if on_tap, do: ~s(data-on-tap="#{on_tap}"), else: ""
    ~s(<button class="dala-button" #{data_attr} style="cursor: pointer;">#{text}</button>)
  end

  defp render_component(:box, props, children) do
    style = build_style(props)
    draggable = props[:draggable]
    droppable = props[:droppable]
    on_long_press = props[:on_long_press]
    on_swipe = props[:on_swipe]

    extra_attrs = ""
    extra_attrs = if draggable, do: extra_attrs <> ~s(data-draggable="#{draggable}"), else: extra_attrs
    extra_attrs = if droppable, do: extra_attrs <> ~s(data-droppable="#{droppable}"), else: extra_attrs
    extra_attrs = if on_long_press, do: extra_attrs <> ~s(data-on-long-press="#{on_long_press}"), else: extra_attrs
    extra_attrs = if on_swipe, do: extra_attrs <> ~s(data-on-swipe="#{on_swipe}"), else: extra_attrs

    ~s(<div class="dala-box" style="#{style}" #{extra_attrs}>#{render_children(children)}</div>)
  end

  defp render_component(:spacer, _props, _children) do
    ~s(<div class="dala-spacer" style="height: 16px;"></div>)
  end

  defp render_component(:divider, _props, _children) do
    ~s(<hr class="dala-divider" />)
  end

  defp render_component(:icon, props, _children) do
    name = props[:name] || "star"
    ~s(<span class="dala-icon" data-icon="#{name}">[#{name}]</span>)
  end

  defp render_component(:toggle, props, _children) do
    on_tap = props[:on_tap]
    data_attr = if on_tap, do: ~s(data-toggle="#{on_tap}"), else: ""
    ~s(<div class="dala-toggle" #{data_attr} data-state="off" style="cursor: pointer;">Toggle</div>)
  end

  defp render_component(:switch, props, _children) do
    on_tap = props[:on_tap]
    data_attr = if on_tap, do: ~s(data-toggle="#{on_tap}"), else: ""
    ~s(<div class="dala-switch" #{data_attr} data-state="off" style="cursor: pointer;">Switch</div>)
  end

  defp render_component(:slider, props, _children) do
    value = props[:value] || 50
    on_change = props[:on_change]
    data_attr = if on_change, do: ~s(data-slider="#{on_change}"), else: ""
    ~s(<input type="range" class="dala-slider" min="0" max="100" value="#{value}" #{data_attr} /><span class="slider-value">#{value}%</span>)
  end

  defp render_component(:progress_bar, props, _children) do
    value = props[:value] || 0
    ~s(<div class="dala-progress-bar" style="width: #{value}%;">#{value}%</div>)
  end

  defp render_component(:text_field, props, _children) do
    placeholder = props[:placeholder] || ""
    value = props[:value] || ""
    on_change = props[:on_change]
    data_attr = if on_change, do: ~s(data-text-input="#{on_change}"), else: ""
    ~s(<input type="text" class="dala-text-field" placeholder="#{placeholder}" value="#{value}" #{data_attr} />)
  end

  defp render_component(:list, props, children) do
    style = build_style(props)
    ~s(<div class="dala-list" style="#{style}">#{render_children(children)}</div>)
  end

  defp render_component(:list_item, props, children) do
    on_tap = props[:on_tap]
    data_attr = if on_tap, do: ~s(data-on-tap="#{on_tap}"), else: ""
    ~s(<div class="dala-list-item" #{data_attr} style="cursor: pointer;">#{render_children(children)}</div>)
  end

  defp render_component(type, props, children) do
    draggable = props[:draggable]
    droppable = props[:droppable]
    on_long_press = props[:on_long_press]
    on_swipe = props[:on_swipe]

    extra_attrs = ""
    extra_attrs = if draggable, do: extra_attrs <> ~s(data-draggable="#{draggable}"), else: extra_attrs
    extra_attrs = if droppable, do: extra_attrs <> ~s(data-droppable="#{droppable}"), else: extra_attrs
    extra_attrs = if on_long_press, do: extra_attrs <> ~s(data-on-long-press="#{on_long_press}"), else: extra_attrs
    extra_attrs = if on_swipe, do: extra_attrs <> ~s(data-on-swipe="#{on_swipe}"), else: extra_attrs

    style = build_style(props)
    ~s(<div class="dala-unknown dala-#{type}" #{extra_attrs} style="#{style}">#{render_children(children)}<small>Unknown: #{type}</small></div>)
  end

  defp render_children(children) when is_list(children) do
    Enum.map(children, &render_ui_tree/1) |> Enum.join("\n")
  end

  defp render_children(_), do: ""

  defp build_style(props) do
    props
    |> Enum.filter(fn {k, _} -> k in [:padding, :padding_top, :padding_right, :padding_bottom, :padding_left, :gap, :background, :border_color, :border_width, :corner_radius, :width, :height] end)
    |> Enum.map(fn {k, v} -> "#{css_property(k)}: #{css_value(v)};" end)
    |> Enum.join(" ")
  end

  defp build_text_style(props) do
    styles = []
    styles = if props[:text_size], do: ["font-size: #{text_size_to_px(props[:text_size])}px" | styles], else: styles
    styles = if props[:text_color], do: ["color: #{color_to_css(props[:text_color])}" | styles], else: styles
    Enum.join(styles, "; ")
  end

  defp css_property(:padding), do: "padding"
  defp css_property(:padding_top), do: "padding-top"
  defp css_property(:padding_right), do: "padding-right"
  defp css_property(:padding_bottom), do: "padding-bottom"
  defp css_property(:padding_left), do: "padding-left"
  defp css_property(:gap), do: "gap"
  defp css_property(:background), do: "background"
  defp css_property(:border_color), do: "border-color"
  defp css_property(:border_width), do: "border-width"
  defp css_property(:corner_radius), do: "border-radius"
  defp css_property(:width), do: "width"
  defp css_property(:height), do: "height"
  defp css_property(_), do: ""

  defp css_value(:space_xs), do: "4px"
  defp css_value(:space_sm), do: "8px"
  defp css_value(:space_md), do: "16px"
  defp css_value(:space_lg), do: "24px"
  defp css_value(:space_xl), do: "32px"
  defp css_value(:radius_sm), do: "4px"
  defp css_value(:radius_md), do: "8px"
  defp css_value(:radius_lg), do: "12px"
  defp css_value(:radius_pill), do: "999px"
  defp css_value(:primary), do: "#2196F3"
  defp css_value(:surface), do: "#FFFFFF"
  defp css_value(:on_surface), do: "#212121"
  defp css_value(:on_primary), do: "#FFFFFF"
  defp css_value(value) when is_binary(value), do: value
  defp css_value(value), do: "#{value}"

  defp text_size_to_px(:xl), do: 24
  defp text_size_to_px(:lg), do: 18
  defp text_size_to_px(:md), do: 14
  defp text_size_to_px(:sm), do: 12
  defp text_size_to_px(:xs), do: 10
  defp text_size_to_px(size) when is_integer(size), do: size
  defp text_size_to_px(_), do: 14

  defp color_to_css(:primary), do: "#2196F3"
  defp color_to_css(:on_primary), do: "#FFFFFF"
  defp color_to_css(:on_surface), do: "#212121"
  defp color_to_css(:surface), do: "#FFFFFF"
  defp color_to_css(color) when is_binary(color), do: color
  defp color_to_css(color), do: "##{color}"

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp html_escape(other), do: "#{other}"

  defp base_css do
    """
    :root {
      --primary: #2196F3;
      --surface: #FFFFFF;
      --on-surface: #212121;
      --background: #F5F5F5;
      --border: #E0E0E0;
      --space-xs: 4px;
      --space-sm: 8px;
      --space-md: 16px;
      --space-lg: 24px;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      margin: 0;
      padding: var(--space-md);
      background: var(--background);
      color: var(--on-surface);
    }
    .dala-preview-container {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-lg);
      max-width: 1600px;
      margin: 0 auto;
    }
    .preview-header {
      width: 100%;
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: var(--space-md);
      padding-bottom: var(--space-md);
      border-bottom: 1px solid var(--border);
    }
    .preview-content {
      flex: 1;
      max-width: 800px;
    }
    .event-log {
      flex: 1;
      max-width: 400px;
      padding: var(--space-md);
      background: #F9F9F9;
      border-radius: 8px;
      border: 1px solid var(--border);
      max-height: 600px;
      overflow-y: auto;
    }
    .event-log h3 {
      margin-top: 0;
      margin-bottom: var(--space-sm);
    }
    .dala-column, .dala-row {
      display: flex;
      flex-direction: column;
    }
    .dala-row {
      flex-direction: row;
    }
    .dala-text {
      margin: 4px 0;
    }
    .dala-button {
      background: var(--primary);
      color: white;
      border: none;
      padding: var(--space-sm) var(--space-md);
      border-radius: 4px;
      cursor: pointer;
      margin: 4px 0;
    }
    .dala-box {
      border: 1px solid var(--border);
      border-radius: 4px;
      padding: var(--space-sm);
      margin: 4px 0;
    }
    .dala-spacer {
      height: 16px;
    }
    .dala-divider {
      border: none;
      border-top: 1px solid var(--border);
      margin: var(--space-sm) 0;
    }
    .dala-icon {
      font-size: 20px;
      margin: 4px;
    }
    .dala-toggle, .dala-switch {
      padding: var(--space-sm) var(--space-md);
      background: #E0E0E0;
      border-radius: 4px;
      margin: 4px 0;
    }
    .dala-slider {
      width: 200px;
    }
    .slider-value {
      margin-left: 8px;
    }
    .dala-progress-bar {
      background: var(--primary);
      color: white;
      text-align: center;
      padding: 4px;
      border-radius: 4px;
      height: 20px;
    }
    .dala-text-field {
      padding: var(--space-sm);
      border: 1px solid var(--border);
      border-radius: 4px;
      margin: 4px 0;
    }
    .dala-list {
      list-style: none;
      padding: 0;
    }
    .dala-list-item {
      padding: var(--space-sm);
      border-bottom: 1px solid var(--border);
    }
    .dala-unknown {
      border: 2px dashed #FF5722;
      padding: var(--space-sm);
      margin: 4px 0;
    }
    [data-on-tap], [data-draggable], [data-droppable], [data-on-long-press], [data-on-swipe] {
      cursor: pointer;
      user-select: none;
      transition: all 0.2s ease;
    }
    [data-draggable] {
      cursor: move;
    }
    [data-droppable] {
      border: 2px dashed var(--primary);
    }
    """
  end

  defp generate_tree_inspector(ui_tree) do
    ~s(
    <div class="component-tree" x-data="{ open: true }">
      <h3 @click="open = !open" style="cursor: pointer;">
        Component Tree <span x-text="open ? '▼' : '▶'"></span>
      </h3>
      <div x-show="open" style="font-family: monospace; font-size: 12px; background: #F0F0F0; padding: 8px; border-radius: 4px;">
        #{inspect(ui_tree, pretty: true) |> html_escape()}
      </div>
    </div>
    )
  end

  defp interactive_js do
    """
    document.addEventListener('DOMContentLoaded', function() {
      var logEntries = document.getElementById('log-entries');
      var eventCount = 0;

      function logEvent(type, target) {
        eventCount++;
        if (eventCount > 50) {
          logEntries.innerHTML = '';
          eventCount = 0;
        }
        var entry = document.createElement('div');
        entry.className = 'log-entry';
        entry.innerHTML = '<strong>' + type + '</strong> ' + target;
        logEntries.appendChild(entry);
      }

      document.querySelectorAll('[data-on-tap]').forEach(function(el) {
        el.addEventListener('click', function(e) {
          logEvent('tap', el.getAttribute('data-on-tap'));
        });
      });

      document.querySelectorAll('[data-toggle]').forEach(function(el) {
        el.addEventListener('click', function(e) {
          var state = el.getAttribute('data-state');
          var newState = state === 'off' ? 'on' : 'off';
          el.setAttribute('data-state', newState);
          el.textContent = 'Toggle: ' + newState;
          logEvent('toggle', el.getAttribute('data-toggle') + ' -> ' + newState);
        });
      });

      document.querySelectorAll('[data-slider]').forEach(function(el) {
        el.addEventListener('input', function(e) {
          var value = el.value;
          var display = el.nextElementSibling;
          if (display) display.textContent = value + '%';
          logEvent('slider_change', el.getAttribute('data-slider') + ' -> ' + value);
        });
      });

      document.querySelectorAll('[data-text-input]').forEach(function(el) {
        el.addEventListener('input', function(e) {
          logEvent('text_change', el.getAttribute('data-text-input') + ' -> ' + el.value);
        });
      });

      document.querySelectorAll('[data-on-long-press]').forEach(function(el) {
        var timer;
        el.addEventListener('mousedown', function(e) {
          timer = setTimeout(function() {
            logEvent('long_press', el.getAttribute('data-on-long-press'));
          }, 500);
        });
        el.addEventListener('mouseup', function(e) {
          clearTimeout(timer);
        });
      });

      document.querySelectorAll('[data-on-swipe]').forEach(function(el) {
        var startX, startY;
        el.addEventListener('touchstart', function(e) {
          startX = e.touches[0].clientX;
          startY = e.touches[0].clientY;
        });
        el.addEventListener('touchend', function(e) {
          var endX = e.changedTouches[0].clientX;
          var endY = e.changedTouches[0].clientY;
          var diffX = endX - startX;
          var diffY = endY - startY;
          if (Math.abs(diffX) > 50 || Math.abs(diffY) > 50) {
            logEvent('swipe', el.getAttribute('data-on-swipe') + ' (' + (diffX > 0 ? 'right' : 'left') + ')');
          }
        });
      });
    });
    """
  end
end
