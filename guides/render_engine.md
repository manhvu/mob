# Render Engine Deep Dive

## Overview

Dala's render engine transfers UI tree data from Elixir (BEAM) to native platforms (iOS/Android) using a JSON-based pipeline. This guide explains the complete flow, implementation details, and tradeoffs.

## Architecture

```
Elixir (Dala.Renderer)
    ↓ 1. Build tree (Elixir structs)
    ↓ 2. Prepare + resolve tokens
    ↓ 3. Encode to JSON
    ↓ 4. Call NIF
    ↓
Rust NIF (dala_nif)
    ↓ 5. Receive JSON string
    ↓ 6. Pass to ObjC/Java
    ↓
Native Bridge (ObjC / Java)
    ↓ 7. Parse JSON to native objects
    ↓ 8. Update UI tree
    ↓
SwiftUI / Jetpack Compose
    ↓ 9. Render to screen
```

## Step-by-Step Pipeline

### 1. Elixir UI Tree Construction

Screens define UI using Elixir structs (or Spark DSL):

```elixir
# In your screen module
def render(_assigns, _socket) do
  ~V"""
  <column>
    <text text="Hello World" />
    <button text="Tap me" on_tap: {self(), :tap}>
  </column>
  """
end
```

This produces a tree of `%Dala.Screen.Node{}` structs:

```elixir
%Dala.Screen.Node{
  type: :column,
  props: %{},
  children: [
    %Dala.Screen.Node{type: :text, props: %{text: "Hello World"}, children: []},
    %Dala.Screen.Node{type: :button, props: %{text: "Tap me", on_tap: {pid, :tap}}, children: []}
  ]
}
```

### 2. Prepare Phase (`Dala.Renderer.prepare/4`)

The `prepare/4` function transforms the tree before JSON encoding:

- **Resolves theme tokens**: Converts `@color.primary` → `"#007AFF"`
- **Applies component defaults**: Adds default props for each component type
- **Handles platform blocks**: Merges `:ios` or `:android` specific props
- **Registers tap handlers**: Converts `{pid, :tag}` tuples to NIF tap handles

Key code in `lib/dala/renderer.ex`:

```elixir
defp prepare(%{type: type, props: props, children: children}, nif, platform, ctx) do
  defaults = Map.get(@component_defaults, type, %{})
  with_defaults = Map.merge(defaults, props)
  prepared_props = prepare_props(with_defaults, nif, platform, ctx)
  prepared_children = Enum.map(children, &prepare(&1, nif, platform, ctx))
  
  %{type: type, props: prepared_props, children: prepared_children}
end
```

### 3. JSON Encoding

The prepared tree is encoded to JSON using `:json.encode/1`:

```elixir
json =
  tree
  |> prepare(nif, platform, ctx)
  |> :json.encode()
  |> IO.iodata_to_binary()
```

Example JSON output:

```json
{
  "type": "column",
  "props": {},
  "children": [
    {
      "type": "text",
      "props": {"text": "Hello World"},
      "children": []
    },
    {
      "type": "button",
      "props": {
        "text": "Tap me",
        "on_tap": "tap_handle_123",
        "accessibility_id": "tap"
      },
      "children": []
    }
  ]
}
```

### 4. NIF Call (Rust)

The JSON string is passed to the Rust NIF via `nif.set_root(json)`:

```rust
// native/dala_nif/src/lib.rs
fn set_root<'a>(env: Env<'a>, json: Term<'a>) -> NifResult<Term<'a>> {
    let json_str: String = json.decode()?;
    let transition = get_transition_and_clear();
    platform_set_root(&json_str, &transition);
    ok(env)
}
```

### 5. Platform Bridge (iOS Example)

The Rust NIF calls Objective-C to pass JSON to the iOS side:

```rust
// native/dala_nif/src/ios.rs
pub fn set_root(json: &str, transition: &str) {
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        let ns_json = ns_string_from_str(json);
        let ns_transition = ns_string_from_str(transition);
        let _: () = msg_send![vm, setRootFromJSON: ns_json, transition: ns_transition];
    }
}
```

### 6. SwiftUI Update

`DalaViewModel` parses JSON and updates the `@Published` property:

```swift
// ios/DalaViewModel.swift
@objc public func setRootFromJSON(_ json: String, transition: String) {
    let data = json.data(using: .utf8)!
    let obj = try JSONSerialization.jsonObject(with: data)
    let node = DalaNode.fromDictionary(obj as! [String: Any])
    setRoot(node, transition: transition)
}
```

SwiftUI observes `root` changes and re-renders:

```swift
// ios/DalaRootView.swift
struct DalaRootView: View {
    @StateObject private var viewModel = DalaViewModel.shared
    
    var body: some View {
        if let root = viewModel.root {
            DalaNodeView(node: root)
                .id(viewModel.navVersion) // Identity changes only on navigation
                .animation(animationForTransition(viewModel.transition))
        }
    }
}
```

## Optimized Path: `render_fast/4`

An optimized version batches tap registrations to reduce NIF calls:

```elixir
def render_fast(tree, platform, nif \\ @default_nif, transition \\ :none) do
  nif.clear_taps()
  nif.set_transition(transition)
  
  {prepared, taps} = prepare_with_taps(tree, nif, platform, ctx)
  
  # Batch register taps (single NIF call)
  nif.set_taps(taps)
  
  json = prepared |> :json.encode() |> IO.iodata_to_binary()
  nif.set_root(json)
end
```

**Benefit**: Reduces NIF calls from N+2 (clear + N register + set_root) to 3 (clear + set_taps + set_root).

## Data Transfer: Pros and Cons

### ✅ Advantages of JSON-based Transfer

1. **Simplicity**
   - Easy to debug (print JSON string)
   - Language-agnostic (any platform can parse JSON)
   - No complex binary serialization

2. **Interoperability**
   - Works with any native platform (iOS, Android, desktop)
   - No need for platform-specific binary formats
   - Can use standard JSON libraries on native side

3. **Inspectability**
   - `Dala.Test.inspect(node)` returns readable tree
   - Can log JSON before sending to NIF
   - Easy to write tests against JSON structure

4. **Flexibility**
   - Easy to add new props (just add to JSON)
   - Platform-specific props handled via `:ios`/`:android` blocks
   - No need to recompile NIF for UI changes

### ❌ Disadvantages of JSON-based Transfer

1. **Performance Overhead**
   - **Encoding**: Elixir → JSON string (CPU + allocation)
   - **Decoding**: JSON → Native objects (CPU + allocation)
   - **String parsing**: `DalaNode.fromDictionary` must parse every prop
   - **Memory**: Intermediate JSON string allocation

2. **Type Safety Loss**
   - JSON is weakly typed (everything is string/number/array/object)
   - Native side must validate and convert types (e.g., `props[@"text_size"]` to `double`)
   - Runtime errors if JSON structure is wrong

3. **No Incremental Updates**
   - Entire tree is re-sent on every render
   - Even if only one text value changed, whole tree is re-encoded
   - SwiftUI's diffing helps, but JSON parsing still happens

4. **NIF Call Overhead**
   - Each `set_root` is a Rust NIF call (context switch)
   - Rust → ObjC message sending (another context switch)
   - Main thread dispatch for UI update

## Performance Considerations

### Throttling

`DalaViewModel` throttles rapid updates (< 16ms) to prevent overwhelming SwiftUI:

```swift
private let minSetRootInterval: TimeInterval = 0.016  // ~60fps

if elapsed < self.minSetRootInterval && transition == "none" {
    return  // Skip this update
}
```

### Identity vs Content Changes

SwiftUI uses `navVersion` (not `root` itself) as view identity:

```swift
.id(viewModel.navVersion)  // Only changes on navigation
```

This prevents full view teardown on state updates (e.g., typing in text field).

### Skip Unchanged Renders

`Dala.Renderer` skips renders when nothing changed (see `AGENTS.md` rule 12):

```elixir
# In Dala.Screen.do_render/3
if no_assigns_changed? && !navigation_occurred? do
  # Skip render, but clear changed tracking
  clear_changed(socket)
  {:noreply, socket}
end
```

## Alternative Approaches (Not Implemented)

### 1. Binary Protocol (e.g., Protocol Buffers)
- **Pros**: Faster encoding/decoding, smaller payload, type-safe
- **Cons**: More complex, requires code generation, less inspectable

### 2. Shared Memory
- **Pros**: Zero-copy between BEAM and native
- **Cons**: Extremely complex, platform-specific, safety issues

### 3. Incremental Patches (like React Fiber)
- **Pros**: Only send changes, not full tree
- **Cons**: Complex diffing logic, need to track previous tree

## Debugging Tips

1. **Log JSON before sending**:
   ```elixir
   json = tree |> prepare(...) |> :json.encode()
   IO.puts("Sending JSON: #{inspect(json)}")
   nif.set_root(json)
   ```

2. **Inspect native tree**:
   ```elixir
   Dala.Test.inspect(node)  # Returns full tree with assigns
   ```

3. **Check NIF calls**:
   ```bash
   adb logcat | grep Dala  # Android
   tail -f ~/Library/Logs/.../app.log  # iOS simulator
   ```

4. **Verify SwiftUI updates**:
   ```swift
   // Add to DalaViewModel.setRoot:
   NSLog("[Dala] Setting root: %@", node?.description ?? "nil")
   ```

## Summary

Dala uses a JSON-based render pipeline that prioritizes simplicity and debuggability over raw performance. The tradeoff is acceptable because:

- UI trees are typically small (< 100 nodes)
- Updates are infrequent (user-driven, not 60fps animations)
- SwiftUI's diffing minimizes actual view updates
- Throttling prevents overwhelming the UI thread

For most apps, this approach works well. If you hit performance issues with very large or rapidly updating UIs, consider:
- Using `render_fast/4` for batched tap registration
- Ensuring `Dala.Screen` skips unchanged renders
- Profiling to identify actual bottlenecks (likely not JSON encoding)
