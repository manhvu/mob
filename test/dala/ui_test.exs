defmodule Dala.UITest do
  use ExUnit.Case, async: true

  alias Dala.UI

  # ── text/1 ───────────────────────────────────────────────────────────────────

  describe "text/1 with keyword list" do
    test "type is :text" do
      assert UI.text(text: "hello").type == :text
    end

    test "props contains the text" do
      assert UI.text(text: "hello").props.text == "hello"
    end

    test "children is always empty — text is a leaf node" do
      assert UI.text(text: "hello").children == []
    end

    test "optional text_color is included when given" do
      assert UI.text(text: "hi", text_color: "#ff0000").props.text_color == "#ff0000"
    end

    test "optional text_size is included when given" do
      assert UI.text(text: "hi", text_size: 18).props.text_size == 18
    end

    test "typography props are included" do
      node =
        UI.text(
          text: "styled",
          font_weight: "bold",
          font_family: "Helvetica",
          text_align: :center,
          italic: true,
          line_height: 1.5,
          letter_spacing: 0.5
        )

      assert node.props.font_weight == "bold"
      assert node.props.font_family == "Helvetica"
      assert node.props.text_align == :center
      assert node.props.italic == true
      assert node.props.line_height == 1.5
      assert node.props.letter_spacing == 0.5
    end

    test "layout props are included" do
      node =
        UI.text(text: "hi", padding: 12, background: :surface, corner_radius: 8, fill_width: true)

      assert node.props.padding == 12
      assert node.props.background == :surface
      assert node.props.corner_radius == 8
      assert node.props.fill_width == true
    end

    test "gesture props are included" do
      node = UI.text(text: "tappable", on_tap: {self(), :tap}, on_long_press: {self(), :long})

      assert node.props.on_tap == {self(), :tap}
      assert node.props.on_long_press == {self(), :long}
    end

    test "accessibility_id is included" do
      assert UI.text(text: "hi", accessibility_id: "greeting").props.accessibility_id ==
               "greeting"
    end

    test "unrecognized props are omitted" do
      props = UI.text(text: "hi", opacity: 0.5, unknown: true).props
      refute Map.has_key?(props, :opacity)
      refute Map.has_key?(props, :unknown)
    end
  end

  describe "text/1 with map" do
    test "accepts a plain map" do
      assert UI.text(%{text: "hello"}).type == :text
    end

    test "produces identical output to keyword list form" do
      assert UI.text(text: "hello", text_size: 16) ==
               UI.text(%{text: "hello", text_size: 16})
    end
  end

  describe "text/1 node shape" do
    test "always has exactly the keys :type, :props, :children" do
      node = UI.text(text: "hi")
      assert Map.keys(node) |> Enum.sort() == [:children, :props, :type]
    end

    test "is renderer-compatible — matches %{type:, props:, children:}" do
      assert %{type: :text, props: %{}, children: []} = UI.text(text: "")
    end
  end

  # ── column/2 ────────────────────────────────────────────────────────────────

  describe "column/2" do
    test "type is :column" do
      assert UI.column([], []).type == :column
    end

    test "children are passed through" do
      children = [UI.text(text: "a"), UI.text(text: "b")]
      assert UI.column([], children).children == children
    end

    test "layout props are included" do
      node =
        UI.column(
          padding: 12,
          gap: 8,
          background: :surface,
          border_color: :primary,
          border_width: 1
        )

      assert node.props.padding == 12
      assert node.props.gap == 8
      assert node.props.background == :surface
      assert node.props.border_color == :primary
      assert node.props.border_width == 1
    end

    test "gesture props are included" do
      node = UI.column(on_tap: {self(), :col_tap}, on_swipe_left: {self(), :swipe})

      assert node.props.on_tap == {self(), :col_tap}
      assert node.props.on_swipe_left == {self(), :swipe}
    end

    test "unrecognized props are omitted" do
      node = UI.column(text: "nope", unknown: true)
      refute Map.has_key?(node.props, :text)
      refute Map.has_key?(node.props, :unknown)
    end
  end

  # ── row/2 ───────────────────────────────────────────────────────────────────

  describe "row/2" do
    test "type is :row" do
      assert UI.row([], []).type == :row
    end

    test "same props as column" do
      node = UI.row(gap: 16, padding: 8, background: :surface)
      assert node.props.gap == 16
      assert node.props.padding == 8
      assert node.props.background == :surface
    end
  end

  # ── box/2 ───────────────────────────────────────────────────────────────────

  describe "box/2" do
    test "type is :box" do
      assert UI.box([], []).type == :box
    end

    test "children are stacked (ZStack)" do
      children = [UI.text(text: "base"), UI.icon(name: "badge")]
      assert UI.box([], children).children == children
    end
  end

  # ── button/1 ────────────────────────────────────────────────────────────────

  describe "button/1" do
    test "type is :button" do
      assert UI.button(text: "OK").type == :button
    end

    test "text prop is set" do
      assert UI.button(text: "Submit").props.text == "Submit"
    end

    test "title prop maps to text for backward compat" do
      assert UI.button(title: "OK").props.text == "OK"
    end

    test "text takes precedence over title" do
      assert UI.button(text: "Submit", title: "OK").props.text == "Submit"
    end

    test "on_tap is included" do
      assert UI.button(text: "OK", on_tap: {self(), :ok}).props.on_tap == {self(), :ok}
    end

    test "disabled is included" do
      assert UI.button(text: "OK", disabled: true).props.disabled == true
    end

    test "styling props are included" do
      node = UI.button(text: "OK", background: :primary, text_color: :white, corner_radius: 12)

      assert node.props.background == :primary
      assert node.props.text_color == :white
      assert node.props.corner_radius == 12
    end

    test "children is always empty" do
      assert UI.button(text: "OK").children == []
    end
  end

  # ── icon/1 ──────────────────────────────────────────────────────────────────

  describe "icon/1" do
    test "type is :icon" do
      assert UI.icon(name: "settings").type == :icon
    end

    test "name prop is set" do
      assert UI.icon(name: "settings").props.name == "settings"
    end

    test "styling props are included" do
      node = UI.icon(name: "star", text_size: 24, text_color: :primary)

      assert node.props.text_size == 24
      assert node.props.text_color == :primary
    end

    test "gesture props are included" do
      node = UI.icon(name: "star", on_tap: {self(), :star_tap})
      assert node.props.on_tap == {self(), :star_tap}
    end
  end

  # ── divider/1 ───────────────────────────────────────────────────────────────

  describe "divider/1" do
    test "type is :divider" do
      assert UI.divider().type == :divider
    end

    test "props are included" do
      node = UI.divider(thickness: 2, color: :primary, padding: 8)
      assert node.props.thickness == 2
      assert node.props.color == :primary
      assert node.props.padding == 8
    end

    test "children is always empty" do
      assert UI.divider().children == []
    end
  end

  # ── spacer/1 ────────────────────────────────────────────────────────────────

  describe "spacer/1" do
    test "type is :spacer" do
      assert UI.spacer().type == :spacer
    end

    test "size prop is included" do
      assert UI.spacer(size: 20).props.size == 20
    end

    test "no size = flexible spacer" do
      assert UI.spacer().props == %{}
    end
  end

  # ── text_field/1 ────────────────────────────────────────────────────────────

  describe "text_field/1" do
    test "type is :text_field" do
      assert UI.text_field().type == :text_field
    end

    test "input props are included" do
      node =
        UI.text_field(
          placeholder: "Enter name",
          on_change: {self(), :changed},
          on_focus: {self(), :focused},
          on_blur: {self(), :blurred},
          on_submit: {self(), :submitted},
          keyboard_type: :email,
          return_key: :next
        )

      assert node.props.placeholder == "Enter name"
      assert node.props.on_change == {self(), :changed}
      assert node.props.on_focus == {self(), :focused}
      assert node.props.on_blur == {self(), :blurred}
      assert node.props.on_submit == {self(), :submitted}
      assert node.props.keyboard_type == :email
      assert node.props.return_key == :next
    end
  end

  # ── toggle/1 ────────────────────────────────────────────────────────────────

  describe "toggle/1" do
    test "type is :toggle" do
      assert UI.toggle().type == :toggle
    end

    test "props are included" do
      node = UI.toggle(value: true, on_change: {self(), :toggled}, text: "Enable")

      assert node.props.value == true
      assert node.props.on_change == {self(), :toggled}
      assert node.props.text == "Enable"
    end
  end

  # ── slider/1 ────────────────────────────────────────────────────────────────

  describe "slider/1" do
    test "type is :slider" do
      assert UI.slider().type == :slider
    end

    test "props are included" do
      node = UI.slider(value: 0.5, min_value: 0, max_value: 100, on_change: {self(), :changed})

      assert node.props.value == 0.5
      assert node.props.min_value == 0
      assert node.props.max_value == 100
      assert node.props.on_change == {self(), :changed}
    end
  end

  # ── tab_bar/1 ───────────────────────────────────────────────────────────────

  describe "tab_bar/1" do
    test "type is :tab_bar" do
      assert UI.tab_bar().type == :tab_bar
    end

    test "props are included" do
      tabs = [%{id: "home", label: "Home"}, %{id: "settings", label: "Settings"}]
      node = UI.tab_bar(tabs: tabs, active_tab: "home", on_tab_select: {self(), :tab})

      assert node.props.tabs == tabs
      assert node.props.active_tab == "home"
      assert node.props.on_tab_select == {self(), :tab}
    end
  end

  # ── video/1 ─────────────────────────────────────────────────────────────────

  describe "video/1" do
    test "type is :video" do
      assert UI.video(src: "https://example.com/clip.mp4").type == :video
    end

    test "props are included" do
      node =
        UI.video(src: "https://example.com/clip.mp4", autoplay: true, loop: true, controls: false)

      assert node.props.src == "https://example.com/clip.mp4"
      assert node.props.autoplay == true
      assert node.props.loop == true
      assert node.props.controls == false
    end
  end

  # ── image/1 ─────────────────────────────────────────────────────────────────

  describe "image/1" do
    test "type is :image" do
      assert UI.image(src: "photo.jpg").type == :image
    end

    test "placeholder_color and accessibility_id are included" do
      node = UI.image(src: "photo.jpg", placeholder_color: :gray_500, accessibility_id: "avatar")

      assert node.props.placeholder_color == :gray_500
      assert node.props.accessibility_id == "avatar"
    end
  end

  # ── switch/1 (backward compat) ──────────────────────────────────────────────

  describe "switch/1" do
    test "type is :switch" do
      assert UI.switch().type == :switch
    end

    test "props are included" do
      node = UI.switch(value: true, on_toggle: {self(), :toggled})

      assert node.props.value == true
      assert node.props.on_toggle == {self(), :toggled}
    end
  end

  # ── scroll/2 ────────────────────────────────────────────────────────────────

  describe "scroll/2" do
    test "type is :scroll" do
      assert UI.scroll([], []).type == :scroll
    end

    test "show_indicator is included" do
      node = UI.scroll(show_indicator: false)
      assert node.props.show_indicator == false
    end

    test "padding and background are included" do
      node = UI.scroll(padding: 12, background: :surface)
      assert node.props.padding == 12
      assert node.props.background == :surface
    end
  end

  # ── list/1 ──────────────────────────────────────────────────────────────────

  describe "list/1" do
    test "maps :data to :items" do
      node = UI.list(id: :my_list, data: ["a", "b", "c"])
      assert node.props.items == ["a", "b", "c"]
    end

    test "empty data defaults to []" do
      node = UI.list(id: :my_list)
      assert node.props.items == []
    end
  end
end
