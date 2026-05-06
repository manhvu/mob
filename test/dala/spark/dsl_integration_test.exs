defmodule Dala.Spark.DslIntegrationTest do
  use ExUnit.Case, async: false

  describe "Spark DSL with all UI components" do
    test "screen with layout containers and children" do
      defmodule TestAllComponentsScreen do
        use Dala.Screen

        screen do
          name(:test_screen)

          column do
            padding(:space_md)
            gap(:space_sm)
            text("Hello World")

            row do
              gap(:space_sm)
              button("Button 1", on_tap: :increment)
              button("Button 2", on_tap: :decrement)
            end
          end
        end

        def handle_event(:increment, _params, socket), do: {:noreply, socket}
        def handle_event(:decrement, _params, socket), do: {:noreply, socket}
      end

      assert Code.ensure_loaded?(TestAllComponentsScreen)

      {:ok, socket} =
        TestAllComponentsScreen.mount(%{}, %{}, Dala.Socket.new(TestAllComponentsScreen))

      render_result = TestAllComponentsScreen.render(socket.assigns)

      assert is_list(render_result)
      [column_node] = render_result
      assert column_node.type == :column
      assert is_list(column_node.children)
      assert length(column_node.children) == 2

      [text_node, row_node] = column_node.children
      assert text_node.type == :text
      assert text_node.props.text == "Hello World"
      assert row_node.type == :row
      assert length(row_node.children) == 2
    end

    test "simple DSL screen with minimal components" do
      defmodule TestSimpleDslScreen do
        use Dala.Screen

        screen do
          name(:simple)
          text("Hello")
        end
      end

      assert Code.ensure_loaded?(TestSimpleDslScreen)

      {:ok, socket} = TestSimpleDslScreen.mount(%{}, %{}, Dala.Socket.new(TestSimpleDslScreen))

      render_result = TestSimpleDslScreen.render(socket.assigns)
      assert is_list(render_result)
      assert length(render_result) == 1
      [text_node] = render_result
      assert text_node.type == :text
      assert text_node.props.text == "Hello"
    end

    test "screen with attributes and @ref syntax" do
      defmodule TestRefScreen do
        use Dala.Screen

        attributes do
          attribute(:count, :integer, default: 0)
        end

        screen do
          name(:ref_test)

          column do
            gap(:space_sm)
            text("Count: @count")
            button("Increment", on_tap: :increment)
          end
        end

        def handle_event(:increment, _params, socket) do
          {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
        end
      end

      assert Code.ensure_loaded?(TestRefScreen)

      {:ok, socket} = TestRefScreen.mount(%{}, %{}, Dala.Socket.new(TestRefScreen))
      assert socket.assigns.count == 0

      render_result = TestRefScreen.render(socket.assigns)
      assert is_list(render_result)
      [column_node | _] = render_result
      assert column_node.type == :column

      [text_node | _] = column_node.children
      assert text_node.type == :text
      assert text_node.props.text == "Count: 0"
    end

    test "screen with attributes generates mount" do
      defmodule TestAttrScreen do
        use Dala.Spark.Dsl

        attributes do
          attribute(:count, :integer, default: 0)
          attribute(:label, :string, default: "Hello")
        end

        screen do
          name(:attr_test)
          text("@label")
        end
      end

      assert Code.ensure_loaded?(TestAttrScreen)

      {:ok, socket} = TestAttrScreen.mount(%{}, %{}, Dala.Socket.new(TestAttrScreen))
      assert socket.assigns.count == 0
      assert socket.assigns.label == "Hello"
    end

    test "all leaf components compile" do
      defmodule TestLeafComponentsScreen do
        use Dala.Screen

        screen do
          name(:leaves)

          column do
            gap(:space_sm)
            text("Hello")
            button("Press", on_tap: :pressed)
            icon("settings")
            divider()
            spacer()
            text_field(placeholder: "Type here", on_change: :changed)
            toggle(value: true, on_change: :toggled)
            slider(value: 0.5, on_change: :slid)
            switch(value: false, on_toggle: :switched)
            image("https://example.com/photo.jpg")
            video("https://example.com/clip.mp4")
            activity_indicator(size: :large)
            progress_bar(progress: 0.5)
            status_bar(bar_style: :light_content)
            refresh_control(on_refresh: :refreshed)
            webview("https://elixir-lang.org")
            camera_preview(facing: :front)
            native_view(SomeModule, id: :my_view)
            tab_bar(tabs: [])
            list(:my_list)
          end
        end

        def handle_event(_, _, socket), do: {:noreply, socket}
      end

      assert Code.ensure_loaded?(TestLeafComponentsScreen)
    end

    test "nested containers compile" do
      defmodule TestNestedScreen do
        use Dala.Screen

        screen do
          name(:nested)

          column do
            padding(:space_md)

            row do
              gap(:space_sm)

              box do
                text("Overlapping")
              end
            end

            scroll do
              padding(:space_sm)
              text("Scrollable")
            end

            pressable do
              on_press(:pressed)
              text("Pressable")
            end

            safe_area do
              text("Safe")
            end

            modal do
              visible(true)
              on_dismiss(:dismissed)
              text("Modal")
            end
          end
        end

        def handle_event(_, _, socket), do: {:noreply, socket}
      end

      assert Code.ensure_loaded?(TestNestedScreen)
    end
  end
end
