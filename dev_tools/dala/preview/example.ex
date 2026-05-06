defmodule Dala.Preview.Example do
  @moduledoc """
  Example UI tree for Dala Preview demonstration.

  This module provides sample UI trees that can be used to test
  the preview functionality.
  """

  @doc """
  Returns a sample UI tree with various components.

  ## Examples

      Dala.Preview.preview(Dala.Preview.Example.ui_tree())

  """
  def ui_tree do
    %{
      type: :column,
      props: %{padding: :md, gap: :sm},
      children: [
        %{
          type: :text,
          props: %{text: "Dala Preview Example", text_size: :xl, text_color: :primary},
          children: []
        },
        %{
          type: :text,
          props: %{text: "This is a demonstration of the preview system."},
          children: []
        },
        %{
          type: :divider,
          props: %{},
          children: []
        },
        %{
          type: :row,
          props: %{gap: :sm},
          children: [
            %{
              type: :button,
              props: %{text: "Tap Me", on_tap: :button_tapped},
              children: []
            },
            %{
              type: :button,
              props: %{text: "Another Button", on_tap: :other_button},
              children: []
            }
          ]
        },
        %{
          type: :text_field,
          props: %{placeholder: "Type something...", on_change: :text_changed},
          children: []
        },
        %{
          type: :toggle,
          props: %{on_tap: :toggle_changed},
          children: []
        },
        %{
          type: :slider,
          props: %{value: 50, on_change: :slider_changed},
          children: []
        },
        %{
          type: :list,
          props: %{},
          children: [
            %{
              type: :list_item,
              props: %{on_tap: :item_1},
              children: [%{type: :text, props: %{text: "List Item 1"}, children: []}]
            },
            %{
              type: :list_item,
              props: %{on_tap: :item_2},
              children: [%{type: :text, props: %{text: "List Item 2"}, children: []}]
            },
            %{
              type: :list_item,
              props: %{on_tap: :item_3},
              children: [%{type: :text, props: %{text: "List Item 3"}, children: []}]
            }
          ]
        }
      ]
    }
  end
end
