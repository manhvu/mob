# Render Engine Deep Dive

## Overview

Dala's render engine transfers UI tree data from Elixir (BEAM) to native platforms (iOS/Android) using a **custom binary protocol**. This guide explains the complete flow, implementation details, and performance characteristics.

## Architecture

```
Elixir (Dala.Renderer)
    ↓ 1. Build tree (Dala.Node structs)
    ↓ 2. Prepare + resolve tokens
    ↓ 3. Encode to binary (encode_tree/1 or encode_frame/1)
    ↓ 4. Call NIF with binary
    ↓
Rust NIF (dala_nif)
    ↓ 5. Receive binary (zero-copy via Rustler Binary<'a>)
    ↓ 6. Parse binary directly
    ↓ 7. Pass to ObjC/Java
    ↓
Native Bridge (ObjC / Java)
    ↓ 8. Convert binary data to native objects
    ↓ 9. Update UI tree
    ↓
SwiftUI / Jetpack Compose
    ↓ 10. Render to screen
```

## Step-by-Step Pipeline

### 1. Elixir UI Tree Construction

Screens define UI using Elixir structs or Spark DSL:

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

This produces a tree of `%Dala.Node{}` structs with stable `:id` fields for reconciliation:

```elixir
%Dala.Node{
  id: "root",
  type: :column,
  props: %{},
  children: [
    %Dala.Node{id: "text1", type: :text, props: %{text: "Hello World"}, children: []},
    %Dala.Node{id: "btn1", type: :button, props: %{text: "Tap me", on_tap: {pid, :tap}}, children: []}
  ]
}
```

### 2. Prepare Phase (`Dala.Renderer.prepare/4`)

The `prepare/4` function transforms the tree before binary encoding:

- **Resolves theme tokens**: Converts `@color.primary` → `"#007AFF"`
- **Applies component defaults**: Adds default props for each component type
- **Handles platform blocks**: Merges `:ios` or `:android` specific props
- **Registers tap handlers**: Converts `{pid, :tag}` tuples to NIF tap handles
- **Generates stable IDs**: Uses `hash_id/1` for deterministic node identification

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

### 3. Binary Encoding

The prepared tree is encoded to a compact binary format using `encode_tree/1` or `encode_frame/1`:

#### Full Tree Encoding

```elixir
# In Dala.Renderer.render/4
node = to_node(tree, "root")
binary = encode_tree(node)
nif.set_root_binary(binary)
```

Binary format (version 2):
```
[u16 version=2][u16 flags][u64 node_count][node1][node2]...[nodeN]
```

#### Incremental Patch Encoding

```elixir
# In Dala.Renderer.render_patches/5
patches = Dala.Diff.diff(old_tree, new_tree)
binary = encode_frame(patches)
nif.apply_patches(binary)
```

Binary format (version 1):
```
[u16 version=1][u16 patch_count][patch1][patch2]...[patchN]
```

### 4. NIF Call (Rust)

The binary is passed to the Rust NIF via `set_root_binary/1` or `apply_patches/1`:

```rust
// native/dala_nif/src/lib.rs
fn set_root_binary(binary: Binary) -> NifResult<Atom> {
    let bytes: &[u8] = binary.as_slice();  // Zero-copy access!
    let transition = get_transition_and_clear();
    platform_set_root_binary(bytes, &transition);
    ok(env)
}
```

**Key benefit**: Rustler's `Binary<'a>` maps directly to BEAM off-heap binaries — no copy occurs at the boundary.

### 5. Platform Bridge (iOS Example)

The Rust NIF calls Objective-C to pass binary data to the iOS side:

```rust
// native/dala_nif/src/ios.rs
pub fn set_root_binary(data: &[u8], transition: &str) {
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        let ns_data = NSData::dataWithBytes(data.as_ptr() as *const c_void, data.len());
        let ns_transition = ns_string_from_str(transition);
        let _: () = msg_send![vm, setRootFromBinary: ns_data, transition: ns_transition];
    }
}
```

### 6. Native UI Update

`DalaViewModel` parses the binary and updates the UI:

```swift
// ios/DalaViewModel.swift
@objc public func setRootFromBinary(_ data: NSData, transition: String) {
    let bytes = data.bytes.bindMemory(to: UInt8.self, capacity: data.length)
    let node = DalaNode.fromBinary(bytes, length: data.length)
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

## Binary Protocol Specification

For complete details on the binary format, see [Binary Protocol](binary_protocol.md).

### Key Format Elements

| Element | Size | Description |
|---------|------|-------------|
| Version | 2 bytes | `2` for full trees, `1` for patches |
| Flags | 2 bytes | Reserved (currently `0`) |
| Node Count | 8 bytes | Total nodes in tree (little-endian) |
| Node ID | 8 bytes | 64-bit hashed identifier (from `hash_id/1`) |
| Node Type | 1 byte | Enum (0=column, 1=row, 2=text, etc.) |
| Property Count | 1 byte | Number of properties (0-255) |
| Properties | Variable | Tagged values (see Binary Protocol guide) |
| Child Count | 4 bytes | Number of children (little-endian) |
| Child IDs | N×8 bytes | Array of child IDs |

### Node Identity (hash_id/1)

Stable node IDs are computed using `:erlang.phash2/2`:

```elixir
defp hash_id(id) do
  id_str = to_string(id)
  lo = :erlang.phash2(id_str, 0xFFFFFFFF)
  hi = :erlang.phash2({id_str, :hi}, 0xFFFFFFFF)
  Bitwise.bor(Bitwise.bsl(hi, 32), lo)
end
```

This ensures deterministic IDs for diffing in `Dala.Diff.diff/2`.

## Incremental Rendering with Diff Engine

Dala supports patch-based UI updates instead of full tree re-renders.

### Architecture

- UI trees use `Dala.Node` struct with stable `:id` field
- `Dala.Diff.diff(old, new)` compares two trees and produces patches
- `Dala.Renderer.render_patches/5` sends only patches to native
- `Dala.Screen` stores previous tree in `__dala__.last_tree`

### Patch Types

| Patch | Format | Description |
|-------|--------|-------------|
| `{:replace, id, node}` | Replace entire node |
| `{:update_props, id, props}` | Update props on existing node |
| `{:insert, parent_id, index, node}` | Insert new node |
| `{:remove, id}` | Remove node |

### Fallback Behavior

If native doesn't support `apply_patches/1`, the system falls back to full render via `set_root_binary/1`.

## Render Functions

### render/4 (Full Render)

```elixir
def render(tree, platform, nif \\ @default_nif, _transition \\ :none) do
  node = to_node(tree, "root")
  binary = encode_tree(node)
  nif.set_root_binary(binary)
  {:ok, :binary_tree}
end
```

### render_fast/4 (Optimized with Tap Batching)

```elixir
def render_fast(tree, platform, nif \\ @default_nif, transition \\ :none) do
  nif.clear_taps()
  nif.set_transition(transition)
  
  {prepared, taps} = encode_tree_with_taps(node, nif, platform, ctx)
  
  # Batch register taps
  nif.set_taps(taps)
  
  nif.set_root_binary(prepared)
  {:ok, :binary_tree}
end
```

### render_patches/5 (Incremental Updates)

```elixir
def render_patches(old_tree, new_tree, platform, nif \\ @default_nif, transition \\ :none) do
  old_node = to_node(old_tree, "old_root")
  new_node = to_node(new_tree, "new_root")
  
  patches = Dala.Diff.diff(old_node, new_node)
  
  if patches == [] do
    # No changes, skip render
    {:ok, []}
  else
    send_patches(patches, new_node, platform, nif, ctx)
    {:ok, patches}
  end
end
```

## Performance Considerations

### Zero-Copy at BEAM↔Rust Boundary

```
Elixir BEAM (off-heap binary) → Rustler Binary<'a> → &[u8]
```

No copying occurs. The binary data is referenced directly via Rustler's `Binary` type.

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

### Throttling (Native Side)

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

## Performance Considerations

### Zero-Copy at BEAM↔Rust Boundary

```
Elixir BEAM (off-heap binary) → Rustler Binary<'a> → &[u8]
```

No copying occurs. The binary data is referenced directly via Rustler's `Binary` type.

### Skip Unchanged Renders

- Node IDs are 64-bit hashed values for stable reconciliation
- Property tags use 1-byte identifiers (tags 1-12 defined, more can be added)
- Enum values (flex_direction, justify_content, etc.) use 1-byte encoding
- Floats (width, height, padding) use little-endian f32 encoding

## Debugging Tips

1. **Inspect the tree** (Elixir side):
   ```elixir
   Dala.Test.inspect(node)  # Returns full tree with assigns
   ```

2. **Check binary size**:
   ```elixir
   binary = Dala.Renderer.encode_tree(node)
   IO.puts("Binary size: #{byte_size(binary)} bytes")
   ```

3. **Verify NIF calls**:
   ```bash
   adb logcat | grep Dala  # Android
   tail -f ~/Library/Logs/.../app.log  # iOS simulator
   ```

4. **Test Diff engine**:
   ```elixir
   old = Dala.Node.from_map(old_map, "root")
   new = Dala.Node.from_map(new_map, "root")
   patches = Dala.Diff.diff(old, new)
   IO.inspect(patches, label: "Patches")
   ```

5. **Verify native patches** (iOS):
   ```swift
   // Add to DalaViewModel.setRootFromBinary:
   NSLog("[Dala] Setting root from binary, size: %d bytes", data.length)
   ```

## Testing

Test files:
- `test/dala/binary_protocol_test.exs` — Binary encoding/decoding
- `test/dala/diff_test.exs` — Diff engine tests

Run tests:
```bash
mix test test/dala/binary_protocol_test.exs
mix test test/dala/diff_test.exs
```

## Summary

Dala uses a **binary protocol** for UI transfer that prioritizes performance and type safety:

- **Full tree encoding** via `encode_tree/1` (version 2 format)
- **Incremental patches** via `encode_frame/1` (version 1 format)
- **Zero-copy** at BEAM↔Rust boundary using Rustler's `Binary<'a>`
- **Stable node IDs** via `hash_id/1` for diffing
- **Patch-based updates** via `Dala.Diff.diff/2`

The binary protocol provides excellent performance with minimal payload sizes.

## References

- [Rustler in Mobile](rustler_complete.md) — Complete guide to Rustler in Dala
