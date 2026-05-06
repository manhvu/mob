# Interactive Preview Example for Dala.Preview

This example demonstrates all the interactive simulation features of the Dala.Preview dev tool.

## Features Demonstrated

1. **Tap simulation** - Click buttons and tappable elements
2. **Long press** - Hold click for 500ms to simulate long press
3. **Drag & Drop** - Drag elements to drop zones
4. **Text input** - Type in text fields and see live updates
5. **Toggle/Switch** - Click to toggle on/off state
6. **Slider** - Drag to adjust values with live feedback
7. **Swipe detection** - Touch swipe events (on touch devices)
8. **Event log** - All interactions are logged in real-time

## Usage

```elixir
# Run this in IEx (dev environment)
MIX_ENV=dev iex -S mix

# Then in IEx:
Dala.Preview.preview(Dala.Preview.Example.ui_tree())
Dala.Preview.preview_and_open(Dala.Preview.Example.ui_tree())
```

Or use the mix task:
```bash
mix dala.preview Dala.Preview.Example
```

## Example UI Tree

The example includes:
- Text elements with different styles
- Buttons with tap handlers
- Toggle and switch components
- Slider with live value display
- Text input field
- Draggable items and drop zones
- List with tappable items
- Elements with long press and swipe handlers
