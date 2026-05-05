defmodule Dala.Spark.DslIntegrationTest do
  use ExUnit.Case, async: false

  describe "Spark DSL with all UI components" do
    test "screen with all components compiles and renders" do
      # Define a test module using the DSL
      defmodule TestAllComponentsScreen do
        use Dala.Screen

        # Define screen with all UI components
        screen "test_screen" do
          column do
            text text: "Hello World"

            row do
              button text: "Button 1", on_tap: :increment
              button text: "Button 2", on_tap: :decrement
            end
          end
        end

        def handle_event(:increment, _params, socket) do
          {:noreply, socket}
        end

        def handle_event(:decrement, _params, socket) do
          {:noreply, socket}
        end
      end

      # Verify the module was defined
      assert Code.ensure_loaded?(TestAllComponentsScreen)

      # Verify mount was generated and works
      {:ok, socket} = TestAllComponentsScreen.mount(%{}, %{}, Dala.Socket.new(TestAllComponentsScreen))

      # Verify render was generated and works
      render_result = TestAllComponentsScreen.render(socket.assigns)

      # Should return a valid render tree
      assert is_map(render_result)
      assert render_result.type == :column
      assert is_list(render_result.children)
      assert length(render_result.children) > 0
    end

    test "simple DSL screen with minimal components" do
      defmodule TestSimpleDslScreen do
        use Dala.Screen

        screen "simple" do
          text text: "Hello"
        end
      end

      assert Code.ensure_loaded?(TestSimpleDslScreen)

      {:ok, socket} = TestSimpleDslScreen.mount(%{}, %{}, Dala.Socket.new(TestSimpleDslScreen))

      render_result = TestSimpleDslScreen.render(socket.assigns)
      assert render_result.type == :text
      assert render_result.props[:text] == "Hello"
    end
  end
end
