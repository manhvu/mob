# Test the WebView Interact API

This is a simple test script to verify the WebView interact API works.

## Prerequisites:

1. Mob project set up
2. iOS simulator or Android emulator running
3. Node.js installed (for local server)

## Test Steps:

### 1. Start local server:

```bash
cd examples
mkdir -p priv/static
# Create the HTML file from examples/webview_interact.examples.md
# Start server
cd priv/static
python3 -m http.server 4000 &
```

### 2. Update your Mob app to use the WebView screen:

```elixir
# In lib/my_app/app.ex
defmodule MyApp do
  use Mob.App, theme: Mob.Theme.Obsidian

  def navigation(_platform) do
    stack(:home, root: MyApp.WebViewScreen)
  end
end
```

### 3. Deploy and connect:

```bash
mix mob.deploy --native
mix mob.connect
```

### 4. Test the interact API:

```elixir
# In IEx
node = :"my_app_ios@127.0.0.1"

# Test tap
Mob.Test.webview_tap(node, ".container > button")

# Test type
Mob.Test.webview_type(node, "#name", "John Doe")

# Test clear
Mob.Test.webview_clear(node, "#email")

# Test eval JS
Mob.Test.webview_eval(node, "document.title")

# Test navigation
Mob.Test.webview_navigate(node, "http://127.0.0.1:4000/other.html")

# Test reload
Mob.Test.webview_reload(node)

# Test screenshot (if implemented)
Mob.Test.webview_screenshot(node)
```

## Expected Results:

1. **Tap**: Should tap the button in WebView
2. **Type**: Should type text into the input field
3. **Clear**: Should clear the input field
4. **Eval JS**: Should return the page title via `handle_info({:webview, :eval_result, ...})`
5. **Navigate**: Should navigate to new URL
6. **Reload**: Should reload the current page
7. **Screenshot**: Should capture WebView content (if implemented)

## Troubleshooting:

1. **JS evaluation not working**: Check that `mob_deliver_webview_eval_result` is properly implemented
2. **Screenshot not working**: Check platform-specific implementation
3. **Messages not received**: Verify `:mob_screen` process is running and `handle_info/2` is implemented

## Next Steps:

1. Implement proper message sending in `mob_deliver_webview_eval_result`
2. Complete Android JNI implementation
3. Implement screenshot capture for both platforms
4. Add more interact actions (drag, swipe, pinch, etc.)
