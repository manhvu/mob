defmodule Dala.PreviewTest do
  use ExUnit.Case, async: true

  describe "preview/2" do
    test "generates HTML for a simple UI tree" do
      ui_tree = %{
        type: :column,
        props: %{padding: :md},
        children: [
          %{type: :text, props: %{text: "Hello"}, children: []},
          %{type: :button, props: %{text: "Click me"}, children: []}
        ]
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "Dala UI Preview"
      assert html =~ "Hello"
      assert html =~ "Click me"
      assert html =~ ~s(class="dala-column")
      assert html =~ ~s(class="dala-text")
      assert html =~ ~s(class="dala-button")
    end

    test "handles list of UI trees" do
      ui_trees = [
        %{type: :text, props: %{text: "First"}, children: []},
        %{type: :text, props: %{text: "Second"}, children: []}
      ]

      html = Dala.Preview.preview(ui_trees)
      assert html =~ "First"
      assert html =~ "Second"
    end
  end

  describe "preview_to_file/3" do
    test "saves HTML to file" do
      ui_tree = %{
        type: :text,
        props: %{text: "Test"},
        children: []
      }

      path = Dala.Preview.preview_to_file(ui_tree, "test_preview.html")
      assert File.exists?(path)

      content = File.read!(path)
      assert content =~ "Test"
      assert content =~ "<!DOCTYPE html>"

      # Cleanup
      File.rm!(path)
    end
  end

  describe "component rendering" do
    test "renders column with styles" do
      ui_tree = %{
        type: :column,
        props: %{padding: :md, gap: :sm, background: :surface},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "padding"
      assert html =~ "gap"
      assert html =~ ~s(class="dala-column")
    end

    test "renders row component" do
      ui_tree = %{
        type: :row,
        props: %{},
        children: [
          %{type: :text, props: %{text: "Item 1"}, children: []},
          %{type: :text, props: %{text: "Item 2"}, children: []}
        ]
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ ~s(class="dala-row")
      assert html =~ "Item 1"
      assert html =~ "Item 2"
    end

    test "renders text with styling" do
      ui_tree = %{
        type: :text,
        props: %{text: "Styled text", text_size: :xl, text_color: :primary},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "Styled text"
      assert html =~ "font-size"
      assert html =~ "color"
    end

    test "renders divider" do
      ui_tree = %{
        type: :divider,
        props: %{},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "<hr"
      assert html =~ "dala-divider"
    end

    test "renders spacer" do
      ui_tree = %{
        type: :spacer,
        props: %{},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "dala-spacer"
    end

    # Interactive feature tests
    test "renders button with tap handler" do
      ui_tree = %{
        type: :button,
        props: %{text: "Tap me", on_tap: :my_tap},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "Tap me"
      assert html =~ ~s(data-on-tap="my_tap")
      assert html =~ "cursor: pointer"
    end

    test "renders toggle with state" do
      ui_tree = %{
        type: :toggle,
        props: %{on_tap: :toggle_handler},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "dala-toggle"
      assert html =~ ~s(data-toggle="toggle_handler")
      assert html =~ ~s(data-state="off")
    end

    test "renders switch component" do
      ui_tree = %{
        type: :switch,
        props: %{on_tap: :switch_handler},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "dala-switch"
      assert html =~ ~s(data-toggle="switch_handler")
    end

    test "renders slider with value" do
      ui_tree = %{
        type: :slider,
        props: %{value: 75, on_change: :slider_change},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ ~s(type="range")
      assert html =~ ~s(value="75")
      assert html =~ ~s(data-slider="slider_change")
      assert html =~ "slider-value"
      assert html =~ "75%"
    end

    test "renders text input field" do
      ui_tree = %{
        type: :text_field,
        props: %{placeholder: "Enter text...", value: "test", on_change: :text_change},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ ~s(type="text")
      assert html =~ ~s(placeholder="Enter text...")
      assert html =~ ~s(value="test")
      assert html =~ ~s(data-text-input="text_change")
    end

    test "renders list with items" do
      ui_tree = %{
        type: :list,
        props: %{},
        children: [
          %{type: :list_item, props: %{on_tap: :item1}, children: [%{type: :text, props: %{text: "Item 1"}, children: []}]},
          %{type: :list_item, props: %{on_tap: :item2}, children: [%{type: :text, props: %{text: "Item 2"}, children: []}]}
        ]
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "dala-list"
      assert html =~ "dala-list-item"
      assert html =~ "Item 1"
      assert html =~ "Item 2"
      assert html =~ ~s(data-on-tap="item1")
    end

    test "renders draggable element" do
      ui_tree = %{
        type: :box,
        props: %{draggable: :drag_item, padding: :sm},
        children: [%{type: :text, props: %{text: "Drag me"}, children: []}]
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ ~s(data-draggable="drag_item")
      assert html =~ "cursor: move"
    end

    test "renders droppable zone" do
      ui_tree = %{
        type: :box,
        props: %{droppable: :drop_zone, padding: :md},
        children: [%{type: :text, props: %{text: "Drop here"}, children: []}]
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ ~s(data-droppable="drop_zone")
      assert html =~ "border: 2px dashed"
    end

    test "renders element with long press" do
      ui_tree = %{
        type: :box,
        props: %{on_long_press: :long_press_handler, padding: :md},
        children: [%{type: :text, props: %{text: "Long press me"}, children: []}]
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ ~s(data-on-long-press="long_press_handler")
      assert html =~ "Long press me"
    end

    test "renders element with swipe handler" do
      ui_tree = %{
        type: :box,
        props: %{on_swipe: :swipe_handler, padding: :md},
        children: [%{type: :text, props: %{text: "Swipe me"}, children: []}]
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ ~s(data-on-swipe="swipe_handler")
      assert html =~ "Swipe me"
    end

    test "handles unknown components gracefully" do
      ui_tree = %{
        type: :unknown_component,
        props: %{custom: "value"},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      assert html =~ "Unknown:"
      assert html =~ "unknown_component"
    end
  end

  describe "HTML structure" do
    test "includes interactive JavaScript" do
      ui_tree = %{type: :button, props: %{text: "Test", on_tap: :test}, children: []}
      html = Dala.Preview.preview(ui_tree)
      assert html =~ "Dala UI Preview - Interactive Simulation Dev Tool"
      assert html =~ "addEventListener"
      assert html =~ "logEvent"
    end

    test "includes event log panel" do
      ui_tree = %{type: :text, props: %{text: "Test"}, children: []}
      html = Dala.Preview.preview(ui_tree)
      assert html =~ "event-log"
      assert html =~ "Event Log"
      assert html =~ "Interact with the preview"
    end

    test "includes CSS for interactive elements" do
      ui_tree = %{type: :text, props: %{text: "Test"}, children: []}
      html = Dala.Preview.preview(ui_tree)
      assert html =~ "cursor: pointer"
      assert html =~ "cursor: move"
      assert html =~ "user-select: none"
      assert html =~ "transition:"
    end

    test "includes Alpine.js for component tree toggle" do
      ui_tree = %{type: :text, props: %{text: "Test"}, children: []}
      html = Dala.Preview.preview(ui_tree, show_tree: true)
      assert html =~ "alpinejs"
      assert html =~ "x-data"
      assert html =~ "x-show"
    end

    test "has proper page title" do
      ui_tree = %{type: :text, props: %{text: "Test"}, children: []}
      html = Dala.Preview.preview(ui_tree, title: "My Custom Preview")
      assert html =~ "<title>My Custom Preview</title>"
    end
  end

  describe "HTML escaping" do
    test "escapes HTML in text" do
      ui_tree = %{
        type: :text,
        props: %{text: "<script>alert('xss')</script>"},
        children: []
      }

      html = Dala.Preview.preview(ui_tree)
      refute html =~ "<script>alert('xss')</script>"
      assert html =~ "&lt;script&gt;"
    end

    test "escapes HTML in component tree display" do
      ui_tree = %{
        type: :text,
        props: %{text: "<b>bold</b>"},
        children: []
      }

      html = Dala.Preview.preview(ui_tree, show_tree: true)
      assert html =~ "&lt;b&gt;bold&lt;/b&gt;"
    end
  end
end
