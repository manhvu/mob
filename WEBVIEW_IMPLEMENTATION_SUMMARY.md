# WebView Implementation Summary

## Overview

This document summarizes the WebView implementation improvements made to the Dala framework, including the new `Dala.WebView.interact/2` API and supporting infrastructure.

## Completed Work

### 1. **`Dala.WebView.interact/2` API** (`dala/lib/dala/webview.ex`)
Created a high-level API for programmatic WebView control:

**Navigation:**
- `navigate/2` - Navigate to URL
- `reload/1` - Reload current page  
- `stop_loading/1` - Stop loading
- `go_forward/1` - Go forward in history

**Interact Actions** (via `interact/2`):
- `{:tap, selector}` - Tap element by CSS selector
- `{:type, selector, text}` - Type text into input
- `{:clear, selector}` - Clear input field
- `{:eval, js_code}` - Evaluate JavaScript
- `{:scroll, selector, dx, dy}` - Scroll element
- `{:wait, selector, timeout_ms}` - Wait for element

**Other:**
- `screenshot/1` - Capture WebView content (stub)
- `eval_js/2` - Evaluate JS and return result
- `post_message/2` - Send message to WebView page

### 2. **iOS WebView Improvements** (`dala/ios/DalaRootView.swift`)
- Added `webView(_:didFinishEvaluatingJavaScript:error:)` delegate method
- Added `takeScreenshot` method (stub)
- Fixed string escaping issues in error handling
- Properly handles JS evaluation results

### 3. **Rust NIF Improvements** (`dala/native/dala_nif/src/lib.rs`)
- Added `CACHED_ENV` static variable using `lazy_static!`
- Implemented `cache_env` NIF to cache Erlang environment
- Added `dala_deliver_webview_eval_result` extern function
  - Receives JSON from ObjC callbacks
  - Logs results (stub for message sending)
  - TODO: Properly send to `:dala_screen` process
- Added `webview_screenshot` NIF (stub)
- Registered all new functions in `rustler::init!` macro

### 4. **Android WebView Stubs** (`dala/native/dala_nif/src/android.rs`)
Documented stubs for:
- `webview_eval_js` - Evaluate JavaScript via JNI
- `webview_post_message` - Send messages via JNI
- `webview_can_go_back` - Check back navigation
- `webview_go_back` - Navigate back
- `webview_screenshot` - Capture WebView content

Each function has TODO comments for JNI implementation.

### 5. **`Dala.Test` WebView Functions** (`dala/lib/dala/test.ex`)
Added testing functions for WebView:
- `webview_eval/2`, `webview_post_message/2`
- `webview_navigate/2`, `webview_reload/1`, `webview_stop_loading/1`, `webview_go_forward/1`
- `webview_tap/2`, `webview_type/3`, `webview_clear/2`
- `webview_screenshot/1`

### 6. **Documentation Updates**
- **`AGENTS.md`**: Added rule #15 documenting the WebView interact API
- **`guides/rustler_in_dala.md`**: Created comprehensive guide for developers:
  - When to use Rustler
  - Project structure
  - Creating NIF functions
  - Platform-specific code
  - Calling ObjC/Swift from Rust (iOS)
  - Calling Java from Rust (Android)
  - Testing strategies
  - Debugging tips
  - Best practices

### 7. **Example Usage** (`dala/examples/webview_interact.examples.md`)
Created comprehensive example demonstrating:
- HTML page with form and JavaScript
- Dala screen using `Dala.WebView.interact/2` API
- Event handlers for WebView messages
- Test scripts using `Dala.Test` functions
- Documentation for CSS selectors, timing, and platform differences

### 8. **Code Quality**
- **Elixir**: `mix format` and `mix credo --strict` pass with no issues
- **Rust**: Code compiles with only deprecation warnings
- Fixed thread safety issue with `CACHED_ENV` (changed from raw pointer to `usize`)

## Remaining Work (TODOs)

### 1. **Proper Message Sending** (`dala_deliver_webview_eval_result`)
**Problem**: Need to send messages from Rust to Erlang `:dala_screen` process.

**Solution**:
```rust
// Get the process ID
let pid = rustler::types::pid::get_local_pid("dala_screen");
if let Ok(pid) = pid {
    // Create the message tuple {:webview, :eval_result, json}
    let webview_atom = rustler::types::atom::Atom::from_str(&env, "webview")
        .unwrap()
        .to_term(&env)
        .unwrap();
    let eval_result_atom = rustler::types::atom::Atom::from_str(&env, "eval_result")
        .unwrap()
        .to_term(&env)
        .unwrap();
    let json_term = rustler::types::binary::Binary::from_bytes(json.as_bytes())
        .to_term(&env)
        .unwrap();
    
    let message = (webview_atom, eval_result_atom, json_term);
    let _ = rustler::env::env_send(&env, pid, message);
}
```

**Challenge**: Getting a valid `Env` outside of NIF calls. The `CACHED_ENV` approach stores the pointer, but we need to properly reconstruct the `Env`.

### 2. **Android JNI Implementation**
Need to implement the JNI calls in `android.rs`:

**`webview_eval_js`**:
```rust
pub fn webview_eval_js(env: &mut JNIEnv, code: &str) {
    if let Some(class) = get_bridge_class(env) {
        let method = "evaluateJavascript";
        let sig = "(Ljava/lang/String;)V";
        if let Ok(code_jstring) = env.new_string(code) {
            let args = [jni::objects::JValue::Object(code_jstring.into())];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}
```

**Challenge**: The NIF functions don't have direct access to JNIEnv. Need to either:
- Pass JNIEnv from the NIF context
- Use JavaVM to attach the thread and get JNIEnv

### 3. **Screenshot Implementation**

**iOS** (`DalaRootView.swift`):
```swift
func takeScreenshot(_ wv: WKWebView, completion: @escaping (Data?) -> Void) {
    let config = WKSnapshotConfiguration()
    wv.takeSnapshot(with: config) { image, error in
        if let image = image {
            completion(image.pngData())
        } else {
            completion(nil)
        }
    }
}
```

**Android** (`android.rs`):
```rust
pub fn webview_screenshot(env: &mut JNIEnv) -> bool {
    // 1. Get WebView instance from dalaBridge
    // 2. Call drawing cache or PixelCopy (API 26+)
    // 3. Compress to PNG and return data
    false
}
```

### 4. **Test the Interact API**
- Deploy the example in `dala/examples/webview_interact.examples.md`
- Verify all interact actions work correctly
- Test on both iOS simulator and Android emulator
- Add unit tests for `Dala.WebView` functions

## Architecture Notes

### Message Flow (WebView JS → Elixir)
```
JavaScript (window.dala.send(data))
    ↓
WKWebView (iOS) / WebView (Android)
    ↓
WKScriptMessageHandler (iOS) / JavascriptInterface (Android)
    ↓
dala_deliver_webview_message() (ObjC) / JNI call (Android)
    ↓
Rust NIF (dala_nif)
    ↓
Erlang process (:dala_screen)
    ↓
handle_info({:webview, :message, data}, socket)
```

### Message Flow (Elixir → WebView JS)
```
Dala.WebView.post_message(socket, data)
    ↓
:dala_nif.webview_post_message(json)
    ↓
platform_webview_post_message() (Rust)
    ↓
evaluateJavascript() / loadUrl("javascript:...") (iOS/Android)
    ↓
window.dala._dispatch(json) (JavaScript)
    ↓
onMessage handlers (JavaScript)
```

## Files Modified

1. `dala/lib/dala/webview.ex` - Added interact API and navigation functions
2. `dala/lib/dala/test.ex` - Added WebView testing functions
3. `dala/ios/DalaRootView.swift` - Added JS evaluation result handling
4. `dala/native/dala_nif/src/lib.rs` - Added cache_env, webview_screenshot, dala_deliver_webview_eval_result
5. `dala/native/dala_nif/src/android.rs` - Updated WebView stubs with JNI signatures
6. `dala/AGENTS.md` - Added rule #15 for WebView interact API
7. `dala/guides/rustler_in_dala.md` - Created Rustler guide (NEW)
8. `dala/examples/webview_interact.examples.md` - Created example (NEW)
9. `dala/test_webview_api.sh` - Created test script (NEW)

## Next Steps

1. **Implement proper message sending** in `dala_deliver_webview_eval_result`
2. **Complete Android JNI implementation** in `android.rs`
3. **Implement screenshot capture** for both platforms
4. **Test the interact API** with the provided example
5. **Add more interact actions** (drag, swipe, pinch, etc.)
6. **Add error handling** for failed JS evaluations
7. **Add timeout handling** for `:wait` action in interact API
