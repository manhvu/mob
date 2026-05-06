# UI Render Pipeline — Deep Technical Guide

> **Version**: v2 (binary protocol, inline strings, no string table)
> **Scope**: Elixir screens → diff engine → binary encoder → Rust NIF → retained UI tree → platform rendering

---

## Table of Contents

1. [Overview](#1-overview)
2. [Elixir Side](#2-elixir-side)
   - 2.1 [Screen declaration (user code)](#21-screen-declaration-user-code)
   - 2.2 [Node struct conversion](#22-node-struct-conversion)
   - 2.3 [The Diff Engine (`Dala.Diff`)](#23-the-diff-engine-daladiff)
   - 2.4 [Binary Protocol v2 Encoder](#24-binary-protocol-v2-encoder)
3. [Native Side (Rust NIF)](#3-native-side-rust-nif)
   - 3.1 [NIF entry point (`lib.rs`)](#31-nif-entry-point-librs)
   - 3.2 [Protocol decoder (`protocol.rs`)](#32-protocol-decoder-protocolrs)
   - 3.3 [Retained UI Tree (`tree.rs`)](#33-retained-ui-tree-treers)
4. [Platform Bridge](#4-platform-bridge)
5. [Full Example: Button Tap](#5-full-example-button-tap)
6. [Key Design Decisions](#6-key-design-decisions)
7. [Debugging](#7-debugging)
8. [Future Work](#8-future-work)

---

This guide covers the full lifecycle of a UI render in Dala: from Elixir
screen code → diff engine → binary protocol → native BEAM NIF → retained
UI tree → platform rendering.

---

## 1. Overview

```
Elixir Screen
    │
    ▼ render/2 or render_patches/5
    │
    ▼ Dala.Node struct tree
    │
    ▼ Dala.Diff.diff/2
    │
    ▼ [patch(), ...]          ← list of tuples
    │
    ▼ Dala.Renderer.encode_frame/1
    │
    ▼ binary (iodata)        ← little-endian, v2 protocol
    │
    ▼ Dala.Native.apply_patches/1
    │
    ▼ Rust NIF: apply_patches/1
    │
    ▼ decode_and_apply/2
    │
    ▼ Tree.apply_patch/1
    │
    ▼ Retained UI tree (HashMap<NodeId, Node>)
         │
         ▼ Layout engine (Flexbox)
         │
         ▼ Platform bridge (SwiftUI / Android Compose)
```

---

## 2. Elixir Side

### 2.1 Screen declaration (user code)

```elixir
defmodule MyApp.HomeScreen do
  use Dala.Screen

  def render(%{assigns: %{count: count}}) do
    ~H"""
    <Column padding={:md}>
      <Text text="Count: #{count}" />
      <Button title="Tap" on_tap={{self(), :tap}} />
    </Column>
    """
  end

  def handle_event(:tap, _, socket) do
    new_count = Dala.Socket.get_assign(socket, :count) + 1
    socket = Dala.Socket.assign(socket, :count, new_count)
    {:noreply, socket}
  end
end
```

The `~H` sigil calls `Dala.UI.column/2`, `Dala.UI.text/2`, etc.
These return **raw maps** like:

```elixir
%{
  type: :column,
  props: %{padding: :md},
  children: [
    %{type: :text, props: %{text: "Count: 0"}},
    %{type: :button, props: %{title: "Tap", on_tap: 42}}
  ]
}
```

### 2.2 Node struct conversion

`Dala.Renderer.render/4` (or `render_patches/5`) calls `to_node/2`
to convert the raw map into a **`Dala.Node` struct**:

```elixir
# renderer.ex
defp to_node(%Dala.Node{} = node, _), do: node
defp to_node(map, default_id) do
  Dala.Node.from_map(map, default_id)
end
```

`Dala.Node.from_map/2` (in `node.ex`):

```elixir
def from_map(%{type: type} = map, default_id) do
  id = map[:id] || Map.get(map, :props, %{})[:id] || default_id

  children =
    Map.get(map, :children, [])
    |> Enum.with_index()
    |> Enum.map(fn {child, idx} ->
         from_map(child, "#{id}:#{idx}")
    end)

  %Dala.Node{
    id: id,
    type: type,
    props: Map.get(map, :props, %{}),
    children: children
  }
end
```

Key points:
- **ID generation**: If no `:id` is provided, it's derived from the parent
  ID + index (e.g., `"root:0"`, `"root:1"`).
- **Recursive**: Children are converted recursively.
- **Stable identity**: The `:id` field is critical for the diff engine.

### 2.3 The Diff Engine (`Dala.Diff`)

When using `render_patches/5` (incremental mode), the renderer
computes the difference between the old and new trees:

```elixir
# renderer.ex — render_patches/5
def render_patches(old_tree, new_tree, platform, nif \\ @default_nif, transition \\ :none) do
  old_node = to_node(old_tree, "root")
  new_node = to_node(new_tree, "root")
  patches = Dala.Diff.diff(old_node, new_node)
  # ...
end
```

`Dala.Diff.diff/2` (in `diff.ex`):

```elixir
def diff(%Node{id: id} = old, %Node{id: id} = new) do
  do_diff(old, new)
end

defp do_diff(%Node{id: id, type: type} = old, %Node{type: type} = new) do
  props_patches = diff_props(old, new)
  children_patches = diff_children(old, new)
  props_patches ++ children_patches
end
```

**Patch types** (produced by `Dala.Diff`):

| Patch | Format | When |
|-------|--------|------|
| `{:replace, id, %Node{}}` | Full node replacement | Type change, or root ID change |
| `{:update_props, id, %{}}` | Props-only update | Same type, props changed |
| `{:insert, parent_id, index, %Node{}}` | Insert new child | New child in updated parent |
| `{:remove, id}` | Remove node | Child no longer present |

**Keyed reconciliation** (in `diff_children/2`):

```elixir
defp diff_children(%Node{id: parent_id, children: old}, %Node{children: new}) do
  old_map = Map.new(old, &{&1.id, &1})
  new_map = Map.new(new, &{&1.id, &1})

  []
  |> diff_removed(old_map, new_map)
  |> diff_inserted(parent_id, old_map, new)
  |> diff_existing(old_map, new_map)
end
```

Nodes are matched by `:id`. If an ID exists in old but not new →
`:remove`. If it exists in new but not old → `:insert`.
If it exists in both → recurse with `diff/2`.

### 2.4 Binary Protocol v2 Encoder

When the diff produces incremental patches (no `:replace`), the renderer
calls `send_patches/4` → `encode_frame/1`:

```elixir
# renderer.ex
defp send_patches(patches, _tree, _platform, nif, _ctx) do
  binary = encode_frame(patches)
  if function_exported?(nif, :apply_patches, 1) do
    nif.apply_patches(binary)
  else
    IO.puts("[Dala] apply_patches not available")
  end
end
```

#### Protocol v2 Format

**Header** (6 bytes):

```
[version: u16-le][patch_count: u16-le]
```

**Opcodes**:

| Opcode | Value | Format |
|--------|-------|--------|
| INSERT | `0x01` | `[u8=1][id:u64-le][parent:u64-le][index:u32-le][type:u8][PROPS]` |
| REMOVE | `0x02` | `[u8=2][id:u64-le]` |
| UPDATE | `0x03` | `[u8=3][id:u64-le][PROPS]` |

**PROPS** (variable length):

```
[field_count: u8]
  repeat field_count times:
    [tag: u8][value...]
```

**Prop tags**:

| Tag | Value | Format | Example |
|-----|-------|--------|---------|
| `:text` | 1 | `[u16-le len][bytes...]` | Inline string |
| `:title` | 2 | `[u16-le len][bytes...]` | Inline string |
| `:color` | 3 | `[u16-le len][bytes...]` | Inline string |
| `:background` | 4 | `[u16-le len][bytes...]` | Inline string |
| `:on_tap` | 5 | `[u64-le]` | Tap handle (integer) |
| `:width` | 6 | `[f32-le]` | Float |
| `:height` | 7 | `[f32-le]` | Float |
| `:padding` | 8 | `[f32-le]` | Float |
| `:flex_grow` | 9 | `[f32-le]` | Float |
| `:flex_direction` | 10 | `[u8]` | 0=Column, 1=Row |
| `:justify_content` | 11 | `[u8]` | 0=Start, 1=Center, 2=End, 3=SpaceBetween |
| `:align_items` | 12 | `[u8]` | 0=Start, 1=Center, 2=End, 3=Stretch |

#### Encoder implementation (in `renderer.ex`)

**`encode_frame/1`** — Entry point:

```elixir
def encode_frame(patches) when is_list(patches) do
  body = Enum.map(patches, &encode_patch/1)

  IO.iodata_to_binary([
    <<1::little-16, length(patches)::little-16>>,
    body
  ])
end
```

Uses `IO.iodata_to_binary/1` for O(n) concatenation (not O(n²) like `<>`).

**`encode_patch/1`** — Dispatches on patch type:

```elixir
defp encode_patch({:insert, parent_id, index, %Node{} = node}) do
  id = hash_id(node.id)
  parent = hash_id(parent_id)

  [
    <<0x01, id::little-64, parent::little-64, index::little-32, kind_to_byte(node.type)::8>>,
    encode_props(node.props),
    encode_children(node.children)
  ]
end

defp encode_patch({:remove, id}) do
  <<0x02, hash_id(id)::little-64>>
end

defp encode_patch({:update_props, id, props}) do
  [<<0x03, hash_id(id)::little-64>>, encode_props(props)]
end

defp encode_patch({:replace, id, %Node{} = node}) do
  # Replace = remove old + insert new
  old_id = hash_id(id)
  new_id = hash_id(node.id)
  [
    <<0x02, old_id::little-64>>,
    <<0x01, new_id::little-64, 0::little-64, 0::little-32, kind_to_byte(node.type)::8>>,
    encode_props(node.props),
    encode_children(node.children)
  ]
end
```

**`encode_props/1`** — Encodes a props map:

```elixir
defp encode_props(props) when is_map(props) do
  {fields, count} = collect_prop_fields(Map.to_list(props), [], 0)
  [<<count::8>>, fields]
end

defp collect_prop_fields([], acc, count), do: {acc, count}

# String fields: inline [u16 len][bytes...]
defp collect_prop_fields([{:text, v} | rest], acc, count) when is_binary(v) do
  collect_prop_fields(rest, [acc, <<1::8, byte_size(v)::little-16, v::binary>>], count + 1)
end

# Integer fields
defp collect_prop_fields([{:on_tap, v} | rest], acc, count) when is_integer(v) do
  collect_prop_fields(rest, [acc, <<5::8, v::little-64>>], count + 1)
end

# Float fields
defp collect_prop_fields([{:width, v} | rest], acc, count) when is_number(v) do
  collect_prop_fields(rest, [acc, <<6::8, v::float-little-32>>], count + 1)
end

# Enum fields (flex_direction, justify_content, align_items)
defp collect_prop_fields([{:flex_direction, v} | rest], acc, count) when is_atom(v) do
  collect_prop_fields(rest, [acc, <<10::8, flex_dir_byte(v)::8>>], count + 1)
end

# Skip non-protocol keys
defp collect_prop_fields([_ | rest], acc, count) do
  collect_prop_fields(rest, acc, count)
end
```

**`hash_id/1`** — Hashes a string ID to u64:

```elixir
defp hash_id(id) do
  id_str = to_string(id)
  lo = :erlang.phash2(id_str, 0xFFFFFFFF)
  hi = :erlang.phash2({id_str, :hi}, 0xFFFFFFFF)
  Bitwise.bor(Bitwise.bsl(hi, 32), lo)
end
```

This produces a u64 that matches the Rust `DefaultHasher` output
(the Rust side uses `std::collections::hash_map::DefaultHasher`).

---

## 3. Native Side (Rust NIF)

### 3.1 NIF entry point (`lib.rs`)

```rust
use rustler::{Binary, Env, NifResult, Term};
use std::sync::Mutex;

mod common;
mod protocol;
mod tree;

use common::*;
use protocol::*;
use tree::*;

lazy_static::lazy_static! {
    static ref TREE: Mutex<Tree> = Mutex::new(Tree::new());
}

#[rustler::nif]
fn apply_patches<'a>(env: Env<'a>, binary: Binary<'a>) -> NifResult<Term<'a>> {
    let bytes = binary.as_slice();  // ZERO-COPY: no allocation
    let mut tree = TREE
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new("tree lock poisoned"))?;
    decode_and_apply(&mut tree, bytes);
    ok(env)
}

rustler::init!("Elixir.Dala.Native");
```

Key point: **`Binary<'a>`** gives zero-copy access to the BEAM binary
memory. No `Vec<u8>` allocation happens at the boundary.

### 3.2 Protocol decoder (`protocol.rs`)

#### Read helpers (zero-copy, little-endian)

```rust
pub fn read_u8(bytes: &[u8], i: &mut usize) -> u8 {
    let val = bytes[*i];
    *i += 1;
    val
}

pub fn read_u16(bytes: &[u8], i: &mut usize) -> u16 {
    let val = u16::from_le_bytes(bytes[*i..*i + 2].try_into().unwrap());
    *i += 2;
    val
}

pub fn read_u64(bytes: &[u8], i: &mut usize) -> u64 {
    let val = u64::from_le_bytes(bytes[*i..*i + 8].try_into().unwrap());
    *i += 8;
    val
}

pub fn read_f32(bytes: &[u8], i: &mut usize) -> f32 {
    let val = f32::from_le_bytes(bytes[*i..*i + 4].try_into().unwrap());
    *i += 4;
    val
}

/// Read an inline string: [u16 len][bytes...]
pub fn read_string_inline(bytes: &[u8], i: &mut usize) -> String {
    let len = read_u16(bytes, i) as usize;
    let s = String::from_utf8_lossy(&bytes[*i..*i + len]).into_owned();
    *i += len;
    s
}
```

#### `decode_and_apply/2` — Main entry point

```rust
pub fn decode_and_apply(tree: &mut Tree, bytes: &[u8]) {
    let mut i = 0;

    // Header: [u16 version][u16 patch_count]
    let version = read_u16(bytes, &mut i);
    if version != VERSION {
        eprintln!("[Dala] Unknown protocol version: {}", version);
        return;
    }

    let patch_count = read_u16(bytes, &mut i) as usize;

    // Decode patches
    for _ in 0..patch_count {
        let opcode = bytes[i];
        i += 1;

        match opcode {
            OP_INSERT => {
                // [u64 id][u64 parent][u32 index][u8 type][PROPS][children...]
                let id = read_u64(bytes, &mut i);
                let parent = read_u64(bytes, &mut i);
                let index = read_u32(bytes, &mut i) as usize;
                let node = decode_node(bytes, &mut i, id);
                tree.apply_patch(Patch::Insert { parent, index, node });
            }
            OP_REMOVE => {
                let id = read_u64(bytes, &mut i);
                tree.apply_patch(Patch::Remove { id });
            }
            OP_UPDATE => {
                let id = read_u64(bytes, &mut i);
                let props = decode_props(bytes, &mut i);
                tree.apply_patch(Patch::UpdateProps { id, props });
            }
            _ => {
                eprintln!("[Dala] Unknown opcode: 0x{:02x}", opcode);
                break;
            }
        }
    }
}
```

#### `decode_node/3` — Decodes a node from the binary stream

```rust
fn decode_node(bytes: &[u8], i: &mut usize, id: NodeId) -> Node {
    let kind = match bytes[*i] {
        NODE_COLUMN => NodeKind::Column,
        NODE_ROW => NodeKind::Row,
        NODE_TEXT => NodeKind::Text,
        // ... other types
        _ => NodeKind::Column,
    };
    *i += 1;

    let props = decode_props(bytes, i);

    let children_count = read_u32(bytes, i) as usize;
    let mut children = Vec::with_capacity(children_count);
    for _ in 0..children_count {
        children.push(read_u64(bytes, i));
    }

    Node {
        id,
        kind,
        props,
        parent: None,
        children,
        layout: Layout::default(),
        dirty_layout: true,
        dirty_paint: true,
    }
}
```

#### `decode_props/2` — Decodes tagged prop fields

```rust
fn decode_props(bytes: &[u8], i: &mut usize) -> Props {
    let field_count = bytes[*i];
    *i += 1;

    let mut props = Props::default();

    for _ in 0..field_count {
        let tag = bytes[*i];
        *i += 1;

        match tag {
            FIELD_TEXT => {
                props.text = Some(read_string_inline(bytes, i));
            }
            FIELD_ON_TAP => {
                props.on_tap = Some(read_u64(bytes, i));
            }
            FIELD_WIDTH => {
                props.width = Some(read_f32(bytes, i));
            }
            FIELD_FLEX_DIRECTION => {
                props.flex_direction = match bytes[*i] {
                    FLEX_ROW => FlexDirection::Row,
                    _ => FlexDirection::Column,
                };
                *i += 1;
            }
            // ... handle other tags
            _ => {
                eprintln!("[Dala] Unknown prop field tag: {}", tag);
            }
        }
    }

    props
}
```

### 3.3 Retained UI Tree (`tree.rs`)

The `Tree` struct holds the current UI state as a HashMap of nodes:

```rust
pub struct Tree {
    pub nodes: HashMap<NodeId, Node>,
    pub root: Option<NodeId>,
    pub dirty_layout: Vec<NodeId>,
    pub dirty_paint: Vec<NodeId>,
}
```

#### `Node` struct

```rust
#[derive(Debug, Clone)]
pub struct Node {
    pub id: NodeId,           // u64, hashed from Elixir ID
    pub kind: NodeKind,        // Column, Row, Text, Button, etc.
    pub props: Props,          // All visual + layout properties
    pub parent: Option<NodeId>,
    pub children: Vec<NodeId>,
    pub layout: Layout,         // Cached layout (x, y, w, h)
    pub dirty_layout: bool,
    pub dirty_paint: bool,
}
```

#### `Props` struct

All properties (content + layout) live in one struct:

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct Props {
    // Content props
    pub text: Option<String>,
    pub title: Option<String>,
    pub color: Option<String>,
    pub background: Option<String>,
    pub on_tap: Option<u64>,

    // Layout props
    pub width: Option<f32>,
    pub height: Option<f32>,
    pub padding: Option<f32>,
    pub flex_grow: Option<f32>,
    pub flex_direction: FlexDirection,
    pub justify_content: JustifyContent,
    pub align_items: AlignItems,
}
```

#### `apply_patch/1` — Applies a single patch

```rust
pub fn apply_patch(&mut self, patch: Patch) {
    match patch {
        Patch::Insert { parent, index, node } => {
            self.insert(parent, index, node);
        }
        Patch::Remove { id } => {
            self.remove(id);
        }
        Patch::UpdateProps { id, props } => {
            self.update_props(id, props);
        }
    }
}
```

**Insert**: Adds a new node under `parent` at `index`. Marks the
subtree as dirty for layout recalculation.

**Remove**: Removes a node and its entire subtree. Cleans up
parent's children list.

**UpdateProps**: Updates props on an existing node. Only marks as
dirty if props actually changed (checked via `PartialEq`).

#### Layout engine (Flexbox)

After all patches are applied, `Tree::recompute_layout()` runs:

```rust
pub fn recompute_layout(&mut self) {
    if let Some(root) = self.root {
        let constraints = Constraints {
            max_width: 0.0,  // filled from platform
            max_height: 0.0,
        };
        self.layout_node(root, constraints);
    }
}
```

The layout engine (in `layout_node`, `layout_column`, `layout_row`)
implements a **subset of Flexbox**:

- `flex_direction: Column | Row`
- `justify_content: Start | Center | End | SpaceBetween`
- `align_items: Start | Center | End | Stretch`
- `flex_grow: f32`
- `width`, `height`, `padding`

After layout, `repaint()` sends the final layout to the platform
bridge (SwiftUI / Android Compose).

---

## 4. Platform Bridge

### iOS (SwiftUI)

The Rust NIF calls into ObjC: `DalaViewModel.setRootFromJSON()`
or `DalaViewModel.applyPatches()`.

SwiftUI views are created/updated based on the retained tree:

```swift
// DalaViewModel.m (ObjC bridge)
- (void)applyPatches:(NSData *)binary {
    // Parse binary patches
    // Update SwiftUI state
    // SwiftUI diffs the state change and re-renders only what changed
}
```

### Android (Jetpack Compose)

Similar flow via JNI → Kotlin/Compose.

---

## 5. Full Example: Button Tap

```
1. User taps button on device
2. iOS: ObjC captures tap, calls `DalaViewModel.onTap(handle: u64)`
3. Rust NIF: `platform_tap(handle)` in `common.rs`
4. `common.rs` looks up the tap handle → Erlang pid
5. `erlang:send(pid, {:webview, :eval_result, ...})` or similar
6. Elixir: `handle_info({:tap, handle}, socket)`
7. User's `handle_event(:tap, handle, socket)` is called
8. State updates: `socket = assign(socket, :count, count + 1)`
9. `Dala.Screen` calls `render/2` with new state
10. `Dala.Diff.diff(old_tree, new_tree)` → `[{:update_props, "t1", %{text: "Count: 1"}}]`
11. `Dala.Renderer.encode_frame(patches)` → binary
12. `Dala.Native.apply_patches(binary)`
13. Rust: `decode_and_apply(&mut tree, bytes)`
14. `Tree::update_props(id, props)` → mark dirty
15. `Tree::recompute_layout()` → recalculate text position
16. SwiftUI re-renders only the text node (incremental!)
```

---

## 6. Key Design Decisions

### 6.1 Why binary protocol instead of JSON?

| Aspect | JSON | Binary v2 |
|--------|-----|----------|
| Encoding speed | Slow (serialization) | Fast (direct binary) |
| Decoding speed | Slow (parsing) | Fast (direct read) |
| Size | ~200-500 bytes | ~50-150 bytes |
| Allocation | Multiple allocations | Zero-copy (BEAM→Rust) |
| Schema | Implicit (JS object) | Explicit (tags + types) |

### 6.2 Why retained tree in Rust?

- **Incremental updates**: Only changed nodes are patched, not
  the entire tree.
- **Layout caching**: `Layout` struct caches position/size. Only
  dirty nodes are recalculated.
- **Subtree removal**: `Tree::remove()` recursively cleans up
  the entire subtree in one operation.

### 6.3 Why `Dala.Node` struct instead of raw maps?

- **Compile-time safety**: `id`, `type`, `props`, `children` are
  verified at compile time in Elixir.
- **Default values**: `props: %{}` and `children: []` are
  set automatically.
- **Documentation**: The struct serves as the schema for the
  entire UI tree.

---

## 7. Debugging

### 7.1 Enable Rust-side logging

```bash
# iOS simulator:
xcrun simctl spawn booted log stream --level debug | grep Dala

# Android:
adb logcat | grep Dala
```

### 7.2 Inspect patches in Elixir

```elixir
# In renderer.ex, add:
defp send_patches(patches, _tree, _platform, nif, _ctx) do
  IO.inspect(patches, label: "Patches")
  # ...
end
```

### 7.3 Test the encoder

```bash
mix test test/dala/diff_test.exs --only "binary protocol v2 encoder"
```

---

## 8. Future Work

1. **Persistent tree across NIF calls**: Use `ResourceArc<Tree>`
   instead of `lazy_static!` + `Mutex`. This allows multiple
   native modules to share the tree.

2. **Dirty flag optimization**: Currently, ALL dirty nodes are
   recalculated. A proper dirty flag system would only recalculate
   the minimal subtree.

3. **Batch layout + paint**: After all patches are applied,
   call `recompute_layout()` + `repaint()` once, not per patch.

4. **String interning** (optional): If strings become a bottleneck,
   add a string table back. For now, inline strings are simpler.

5. **`UpdateStyle` patch**: If style-only changes become common,
   add a dedicated `UpdateStyle` patch that skips content
   prop decoding.
