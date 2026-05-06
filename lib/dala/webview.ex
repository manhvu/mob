defmodule Dala.WebView do
  @compile {:nowarn_undefined, [:dala_nif, :Nx]}
  @moduledoc """
  Bidirectional JS bridge for the native WebView component.

  ## Overview:

  Use `Dala.UI.webview/1` to embed the component, then call these functions
  from `handle_info` to communicate with the page.

  ## JS Side (injected automatically):

      // Send a message to Elixir
      window.dala.send({ event: "clicked", id: 42 })

      // Receive a message from Elixir
      window.dala.onMessage(function(data) { console.log(data) })

  ## Elixir Side:

      def handle_info({:webview, :message, %{"event" => "clicked", "id" => id}}, socket) do
        {:noreply, socket}
      end

      def handle_info({:webview, :blocked, url}, socket) do
        # A navigation attempt was blocked by the allow: whitelist
        {:noreply, socket}
      end

  ## Navigation Functions:

  - `navigate/2` - Navigate to URL
  - `reload/1` - Reload current page
  - `stop_loading/1` - Stop loading
  - `go_forward/1` - Go forward in history

  ## Interact Actions:

  - `{:tap, selector}` - Tap an element
  - `{:type, selector, text}` - Type text
  - `{:clear, selector}` - Clear input
  - `{:eval, js_code}` - Evaluate JavaScript
  - `{:scroll, selector, dx, dy}` - Scroll element
  - `{:wait, selector, timeout_ms}` - Wait for element

  Results arrive via:
  - `{:webview, :eval_result, json}` - JS eval result
  - `{:webview, :interact_result, %{"action" => ..., "success" => ...}}`
  """

  @doc """
  Evaluate arbitrary JavaScript in the current WebView and return the result
  asynchronously via `handle_info({:webview, :eval_result, result}, socket)`.

  The result is JSON-decoded before delivery.
  """
  @spec eval_js(Dala.Socket.t(), String.t()) :: Dala.Socket.t()
  def eval_js(socket, code) when is_binary(code) do
    :dala_nif.webview_eval_js(code)
    socket
  end

  @doc """
  Navigate to a new URL in the WebView.
  """
  @spec navigate(Dala.Socket.t(), String.t()) :: Dala.Socket.t()
  def navigate(socket, url) when is_binary(url) do
    js = "window.location.href = #{Jason.encode!(url)}"
    :dala_nif.webview_eval_js(js)
    socket
  end

  @doc """
  Reload the current page.
  """
  @spec reload(Dala.Socket.t()) :: Dala.Socket.t()
  def reload(socket) do
    :dala_nif.webview_eval_js("window.location.reload()")
    socket
  end

  @doc """
  Stop loading the current page.
  """
  @spec stop_loading(Dala.Socket.t()) :: Dala.Socket.t()
  def stop_loading(socket) do
    :dala_nif.webview_eval_js("window.stop()")
    socket
  end

  @doc """
  Go forward in the WebView history (if possible).
  """
  @spec go_forward(Dala.Socket.t()) :: Dala.Socket.t()
  def go_forward(socket) do
    :dala_nif.webview_eval_js("if (window.history.length > 1) window.history.forward()")
    socket
  end

  @doc """
  High-level interact API for driving WebView content programmatically.

  Actions:
    * `{:tap, selector}` - Tap an element matching CSS selector
    * `{:type, selector, text}` - Type text into an input element
    * `{:clear, selector}` - Clear an input element
    * `{:eval, js_code}` - Evaluate JS and return result via `:eval_result`
    * `{:scroll, selector, dx, dy}` - Scroll an element by delta
    * `{:wait, selector, timeout_ms}` - Wait for element to appear (via polling)

  Results arrive as `handle_info({:webview, :interact_result, %{"action" => ..., "success" => ...}}, socket)`.
  """
  @spec interact(Dala.Socket.t(), tuple()) :: Dala.Socket.t()
  def interact(socket, action) do
    js = interact_js(action)
    :dala_nif.webview_eval_js(js)
    socket
  end

  defp interact_js({:tap, selector}) when is_binary(selector) do
    """
    (function() {
      var el = document.querySelector(#{Jason.encode!(selector)});
      if (el) { el.click(); return {action: "tap", success: true, selector: #{Jason.encode!(selector)}}; }
      return {action: "tap", success: false, error: "Element not found"};
    })()
    """
  end

  defp interact_js({:type, selector, text}) when is_binary(selector) and is_binary(text) do
    """
    (function() {
      var el = document.querySelector(#{Jason.encode!(selector)});
      if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
        el.value = #{Jason.encode!(text)};
        el.dispatchEvent(new Event('input', {bubbles: true}));
        return {action: "type", success: true, selector: #{Jason.encode!(selector)}};
      }
      return {action: "type", success: false, error: "Input element not found"};
    })()
    """
  end

  defp interact_js({:clear, selector}) when is_binary(selector) do
    """
    (function() {
      var el = document.querySelector(#{Jason.encode!(selector)});
      if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
        el.value = '';
        el.dispatchEvent(new Event('input', {bubbles: true}));
        return {action: "clear", success: true};
      }
      return {action: "clear", success: false};
    })()
    """
  end

  defp interact_js({:eval, code}) when is_binary(code) do
    code
  end

  defp interact_js({:scroll, selector, dx, dy})
       when is_binary(selector) and is_number(dx) and is_number(dy) do
    """
    (function() {
      var el = document.querySelector(#{Jason.encode!(selector)});
      if (el) { el.scrollLeft += #{dx}; el.scrollTop += #{dy}; return {action: "scroll", success: true}; }
      return {action: "scroll", success: false};
    })()
    """
  end

  defp interact_js({:wait, selector, timeout_ms})
       when is_binary(selector) and is_integer(timeout_ms) do
    """
    (function() {
      var timeout = #{timeout_ms};
      var interval = 100;
      var elapsed = 0;
      var check = function() {
        if (document.querySelector(#{Jason.encode!(selector)})) {
          return {action: "wait", success: true, selector: #{Jason.encode!(selector)}};
        }
        elapsed += interval;
        if (elapsed >= timeout) {
          return {action: "wait", success: false, error: "Timeout waiting for element"};
        }
        setTimeout(check, interval);
      };
      check();
    })()
    """
  end

  defp interact_js(_), do: "throw new Error('Unknown interact action')"

  @doc """
  Take a screenshot of the WebView content.

  Returns the PNG data as a binary via:

      handle_info({:webview, :screenshot, png_data}, socket)

  Note: Currently not implemented on all platforms.
  """
  @spec screenshot(Dala.Socket.t()) :: Dala.Socket.t()
  def screenshot(socket) do
    :dala_nif.webview_screenshot()
    socket
  end

  @doc """
  Push a message from Elixir into the WebView page. Calls `window.dala._dispatch(json)`
  in JS, which delivers the data to all `window.dala.onMessage` handlers.
  """
  @spec post_message(Dala.Socket.t(), term()) :: Dala.Socket.t()
  def post_message(socket, data) do
    json = :json.encode(data)
    :dala_nif.webview_post_message(json)
    socket
  end
end
