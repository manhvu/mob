# WebView Interact API Example

This example demonstrates how to use the `Dala.WebView.interact/2` API to programmatically control WebView content.

## Prerequisites

- Dala project set up with `mix dala.new`
- iOS simulator or Android device/emulator running
- Node.js installed (for the example local server)

## Example: WebView with Interact API

### 1. Create a simple HTML page (`priv/static/index.html`):

```html
<!DOCTYPE html>
<html>
<head>
    <title>WebView Test</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        .input-group { margin: 10px 0; }
        label { display: block; margin-bottom: 5px; }
        input { width: 100%; padding: 8px; box-sizing: border-box; }
        button { 
            background: #007AFF; 
            color: white; 
            border: none; 
            padding: 10px 20px; 
            border-radius: 5px; 
            cursor: pointer;
        }
        #result { 
            margin-top: 20px; 
            padding: 10px; 
            background: #f0f0f0; 
            border-radius: 5px; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>WebView Interact API Test</h1>
        
        <div class="input-group">
            <label for="name">Name:</label>
            <input type="text" id="name" placeholder="Enter your name">
        </div>
        
        <div class="input-group">
            <label for="email">Email:</label>
            <input type="email" id="email" placeholder="Enter your email">
        </div>
        
        <button onclick="submitForm()">Submit</button>
        
        <div id="result"></div>
    </div>
    
    <script>
        // Set up dala bridge
        if (!window.dala) {
            window.dala = {
                send: function(data) {
                    window.webkit.messageHandlers.dala.postMessage(JSON.stringify(data));
                },
                onMessage: function(handler) {
                    if (!window._dalaHandlers) window._dalaHandlers = [];
                    window._dalaHandlers.push(handler);
                    return function() {
                        window._dalaHandlers = window._dalaHandlers.filter(h => h !== handler);
                    };
                },
                _dispatch: function(json) {
                    try {
                        var data = JSON.parse(json);
                        if (window._dalaHandlers) {
                            window._dalaHandlers.forEach(h => h(data));
                        }
                    } catch(e) {}
                }
            };
        }
        
        function submitForm() {
            const name = document.getElementById('name').value;
            const email = document.getElementById('email').value;
            
            const result = document.getElementById('result');
            result.innerHTML = `<h3>Submitted:</h3>
                <p>Name: ${name}</p>
                <p>Email: ${email}</p>`;
            
            // Send to Elixir
            window.dala.send({
                type: 'form_submit',
                name: name,
                email: email
            });
        }
        
        // Listen for messages from Elixir
        window.dala.onMessage(function(data) {
            console.log('Received from Elixir:', data);
            const result = document.getElementById('result');
            result.innerHTML += `<p><strong>From Elixir:</strong> ${JSON.stringify(data)}</p>`;
        });
    </script>
</body>
</html>
```

### 2. Create the Dala screen (`lib/my_app/webview_screen.ex`):

```elixir
defmodule MyApp.WebViewScreen do
  use Dala.Screen

  def mount(_params, _session, socket) do
    {:ok, Dala.Socket.assign(socket, :status, "ready")}
  end

  def render(assigns) do
    %{
      type: :column,
      props: %{padding: 20, gap: 10},
      children: [
        %{type: :text, props: %{text: "WebView Interact Example", text_size: :xl, font_weight: :bold},
        %{type: :text, props: %{text: "Status: #{assigns.status}", text_color: :secondary},
        Dala.UI.webview(
          url: "http://127.0.0.1:4000/index.html",
          allow: ["http://127.0.0.1:4000"],
          width: 400,
          height: 600
        ),
        %{type: :button, props: %{text: "Tap Submit Button", on_tap: {self(), :tap_submit}},
        %{type: :button, props: %{text: "Type in Name Field", on_tap: {self(), :type_name}},
        %{type: :button, props: %{text: "Clear Fields", on_tap: {self(), :clear_fields}},
        %{type: :button, props: %{text: "Evaluate JS", on_tap: {self(), :eval_js}},
        %{type: :text, props: %{text: "Message from WebView: #{assigns.webview_message || "none"}}
      ]
    }
  end

  def handle_event("tap", %{"tag" => "tap_submit"}, socket) do
    # Tap the submit button in WebView
    Dala.WebView.interact(socket, {:tap, ".container > button"})
    {:noreply, socket}
  end

  def handle_event("tap", %{"tag" => "type_name"}, socket) do
    # Type into the name field
    Dala.WebView.interact(socket, {:type, "#name", "John Doe"})
    {:noreply, socket}
  end

  def handle_event("tap", %{"tag" => "clear_fields"}, socket) do
    # Clear both fields
    Dala.WebView.interact(socket, {:clear, "#name"})
    Dala.WebView.interact(socket, {:clear, "#email"})
    {:noreply, socket}
  end

  def handle_event("tap", %{"tag" => "eval_js"}, socket) do
    # Evaluate JavaScript
    Dala.WebView.eval_js(socket, "document.title")
    {:noreply, socket}
  end

  def handle_info({:webview, :message, data}, socket) do
    {:noreply, Dala.Socket.assign(socket, :webview_message, inspect(data))}
  end

  def handle_info({:webview, :eval_result, result}, socket) do
    {:noreply, Dala.Socket.assign(socket, :webview_message, "JS Result: #{inspect(result)}")}
  end

  def handle_info({:webview, :interact_result, data}, socket) do
    {:noreply, Dala.Socket.assign(socket, :webview_message, "Interact: #{inspect(data)}")}
  end
end
```

### 3. Start a local server for the HTML:

```bash
cd priv/static
python3 -m http.server 4000
```

### 4. Update your app to use the WebView screen:

```elixir
defmodule MyApp do
  use Dala.App

  def navigation(_platform) do
    stack(:home, root: MyApp.WebViewScreen)
  end
end
```

### 5. Deploy and test:

```bash
mix dala.deploy --native
mix dala.connect
```

### 6. Test the interact API using Dala.Test:

```elixir
node = :"my_app_ios@127.0.0.1"

# Tap the submit button
Dala.Test.webview_tap(node, ".container > button")

# Type into name field
Dala.Test.webview_type(node, "#name", "John Doe")

# Clear fields
Dala.Test.webview_clear(node, "#email")

# Evaluate JavaScript
Dala.Test.webview_eval(node, "document.title")
```

## Testing the API

You can also test the API programmatically:

```elixir
# In IEx after connecting to the node
alias Dala.Test, as: T

# Navigate to a new URL
T.webview_navigate(node, "http://127.0.0.1:4000/other-page.html")

# Reload the page
T.webview_reload(node)

# Take a screenshot (if implemented)
T.webview_screenshot(node)
```

## Notes

1. **CSS Selectors**: The interact API uses standard CSS selectors. Make sure your selectors are specific enough to uniquely identify elements.

2. **Timing**: WebView operations are asynchronous. The results come back via `handle_info` callbacks.

3. **iOS vs Android**: The underlying implementation differs by platform:
   - iOS: Uses `WKWebView` and `WKScriptMessageHandler`
   - Android: Uses `WebView` and JavaScript evaluation

4. **Error Handling**: Always handle the `:error` case in your `handle_info` callbacks.

## Next Steps

- Implement full `dala_deliver_webview_eval_result` in Rust to properly send messages to Elixir
- Complete Android WebView JNI implementation
- Add screenshot capture for both platforms
- Add more interact actions (scroll, wait, etc.)
