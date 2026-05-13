# Binary Protocol — Dala UI Render Pipeline

## Overview

Dala's UI render pipeline uses a **custom binary protocol** to transfer UI trees and incremental patches from Elixir (BEAM) to the native side (Rust NIF → SwiftUI/Compose).

### Key Benefits

1. **Zero-copy at boundary**: Rustler's `Binary<'a>` maps directly to BEAM off-heap binaries
2. **No parsing overhead**: Rust NIF reads structured binary data directly
3. **Compact encoding**: Binary format is 3-5x smaller than JSON
4. **Type-safe**: Well-defined format with versioning support

---

## Binary Format Specification

### Version History

| Version | Used For | Description |
|---------|----------|-------------|
| 3 | Full Trees & Patches | Current format — magic header, SHA-256 node IDs, extended tags |

> **Note:** Versions 1 and 2 are deprecated. All current tooling uses version 3.

---

## Full Tree Format (Version 3)

Used by `Dala.Ui.Renderer.encode_tree/1` and `Dala.Platform.Native.set_root_binary/1`.

### Header

```
[2 bytes magic 0xD100][2 bytes version=3][8 bytes node_count]
```

| Field | Size | Description |
|-------|------|-------------|
| magic | 2 bytes | `0xD1, 0x00` — identifies Dala protocol |
| version | 2 bytes | Always `3` (little-endian) |
| node_count | 8 bytes | Total number of nodes in the tree (little-endian) |

### Node Encoding

Each node is encoded as:

```
[u64 id][u8 type][u8 field_count][props...][u32 child_count][u64 child_ids...]
```

#### Node ID (8 bytes)
A 64-bit hashed identifier for the node, computed by `Dala.Ui.Renderer.hash_id/1`:

```elixir
defp hash_id(id) do
  id_str = to_string(id)
  <<hash::unsigned-64-big, _rest::binary>> = :crypto.hash(:sha256, id_str)
  hash
end
```

This ensures stable, deterministic IDs for diffing using SHA-256 hashing.

#### Node Type (1 byte)

| Byte Value | Atom |
|------------|------|
| 0 | `:column` |
| 1 | `:row` |
| 2 | `:text` |
| 3 | `:button` |
| 4 | `:image` |
| 5 | `:scroll` |
| 6 | `:webview` |
| 7+ | Custom / plugin types |
| 0 (default) | Unknown types default to 0 |

#### Property Count (1 byte)
Number of properties encoded for this node (0-255).

#### Properties (variable)
Each property is encoded as:

```
[u8 tag][value...]
```

See **Property Encoding** section below. Tags now extend to 16+ for new component properties.

#### Child Count (4 bytes)
Number of children this node has (little-endian u32).

#### Child IDs (variable)
Array of `child_count × 8 bytes`, each child ID is a u64 (little-endian).

---

## Patch Frame Format (Version 3)

Used by `Dala.Ui.Renderer.encode_frame/1` and `Dala.Platform.Native.apply_patches/1`.

### Header

```
[2 bytes magic 0xD100][2 bytes version=3][2 bytes flags][2 bytes patch_count]
```

| Field | Size | Description |
|-------|------|-------------|
| magic | 2 bytes | `0xD1, 0x00` — identifies Dala protocol |
| version | 2 bytes | Always `3` (little-endian) |
| flags | 2 bytes | Reserved (currently `0`) |
| patch_count | 2 bytes | Number of patches in this frame (little-endian) |

### Patch Opcodes

#### `op_patch_node` (0x04)

```
[u8 opcode=0x04][u64 id][u8 field_mask][props...]
```

Update specific fields on a node by bitmask. More efficient than a full property update.

#### `op_set_text` (0x05)

```
[u8 opcode=0x05][u64 id][u16 len][bytes]
```

Fast-path for text-only updates on `:text` and `:button` nodes.

#### `op_set_style` (0x06)

```
[u8 opcode=0x06][u64 id][u8 style_tag][u8 style_value]
```

Update a single style property (e.g., color, padding) without a full props map.

#### `op_register_string` (0x07)

```
[u8 opcode=0x07][u64 id][u16 len][bytes]
```

Pre-register a string with the native side for faster subsequent references.

#### `op_event` (0x08)

```
[u8 opcode=0x08][u64 id][u8 event_type][payload...]
```

Event delivery from native to Elixir (reverse direction).

#### `op_frame_begin` (0x09)

```
[u8 opcode=0x09]
```

Delimits the start of a frame. Used for frame boundary detection.

#### `op_frame_end` (0x0A)

```
[u8 opcode=0x0A]
```

Delimits the end of a frame.

#### INSERT (0x01)

```
[u8 opcode=0x01][u64 id][u64 parent_id][u32 index][u8 type][props...]
```

Insert a new node under `parent_id` at position `index`.

#### REMOVE (0x02)

```
[u8 opcode=0x02][u64 id]
```

Remove the node with the given `id`.

#### UPDATE (0x03)

```
[u8 opcode=0x03][u64 id][props...]
```

Update properties on the node with the given `id`.

---

## Property Encoding

Properties are encoded as tagged values. The `field_count` byte in the node header indicates how many properties follow.

### Property Tags

| Tag | Name | Value Format | Elixir Type |
|-----|------|--------------|-------------|
| 1 | `:text` | `[u16 len][bytes]` | binary string |
| 2 | `:title` | `[u16 len][bytes]` | binary string |
| 3 | `:color` | `[u16 len][bytes]` | binary string (e.g., "red") |
| 4 | `:background` | `[u16 len][bytes]` | binary string |
| 5 | `:on_tap` | `[u64 handle]` | NIF tap handle (integer) |
| 6 | `:width` | `[f32]` | float (little-endian) |
| 7 | `:height` | `[f32]` | float (little-endian) |
| 8 | `:padding` | `[f32]` | float (little-endian) |
| 9 | `:flex_grow` | `[f32]` | float (little-endian) |
| 10 | `:flex_direction` | `[u8]` | byte (0=column, 1=row) |
| 11 | `:justify_content` | `[u8]` | byte (0=start, 1=center, 2=end, 3=space_between) |
| 12 | `:align_items` | `[u8]` | byte (0=start, 1=center, 2=end, 3=stretch) |
| 13+ | *(extended)* | *varies* | Reserved for new component properties |

### Enum Encoding

#### Flex Direction (tag 10)

| Byte | Atom |
|------|------|
| 0 | `:column` (default) |
| 1 | `:row` |

#### Justify Content (tag 11)

| Byte | Atom |
|------|------|
| 0 | `:start` (default) |
| 1 | `:center` |
| 2 | `:end` |
| 3 | `:space_between` |

#### Align Items (tag 12)

| Byte | Atom |
|------|------|
| 0 | `:start` (default) |
| 1 | `:center` |
| 2 | `:end` |
| 3 | `:stretch` |

---

## Implementation Details

### Elixir Side (Encoder)

Located in `lib/dala/ui/renderer.ex`:

```elixir
# Full tree encoding
Dala.Ui.Renderer.encode_tree(%Dala.Node{} = node)

# Patch frame encoding
Dala.Ui.Renderer.encode_frame([patch1, patch2, ...])

# Hash function for stable node IDs (SHA-256)
Dala.Ui.Renderer.hash_id(id)  # returns u64 integer
```

### Rust NIF Side (Decoder)

The Rust NIF (`native/dala_nif/src/protocol.rs`) receives binaries via Rustler:

```rust
#[rustler::nif]
fn set_root_binary(binary: Binary) -> NifResult<Atom> {
    let bytes: &[u8] = binary.as_slice();
    // Parse header: magic (0xD100), version (3), node_count
    // Then parse each node...
}
```

Rustler's `Binary` type provides zero-copy access to BEAM off-heap binaries.

---

## Usage Examples

### Encoding a Full Tree

```elixir
node = %Dala.Node{
  id: "root",
  type: :column,
  props: %{padding: 10, background: "blue"},
  children: [
    %Dala.Node{
      id: "text1",
      type: :text,
      props: %{text: "Hello World"},
      children: []
    }
  ]
}

binary = Dala.Ui.Renderer.encode_tree(node)
# => <<209, 0, 3, 0, 0, 0, 0, 0, 0, 0, 2, ...>>
```

### Encoding Patches

```elixir
patches = [
  {:remove, "old_node"},
  {:update_props, "node1", %{text: "Updated"}},
  {:insert, "parent", 0, %Dala.Node{...}}
]

binary = Dala.Ui.Renderer.encode_frame(patches)
# => <<209, 0, 3, 0, 2, 0, ...>>
```

### In Render Functions

```elixir
# Dala.Ui.Renderer.render/4 now uses binary protocol
def render(tree, platform, nif \\ @default_nif, _transition \\ :none) do
  node = to_node(tree, "root")
  binary = encode_tree(node)
  nif.set_root_binary(binary)  # Instead of nif.set_root(json)
  {:ok, :binary_tree}
end
```

---

## Testing

Test file: `test/dala/binary_protocol_test.exs`

```elixir
# Example test
test "encodes a simple text node" do
  node = %Dala.Node{
    id: "text1",
    type: :text,
    props: %{text: "Hello"},
    children: []
  }

  binary = Dala.Ui.Renderer.encode_tree(node)
  assert is_binary(binary)
  assert byte_size(binary) > 10
end
```

Run tests:
```bash
mix test test/dala/binary_protocol_test.exs
```

---

## Performance Considerations

### Zero-Copy Boundary

```
Elixir BEAM (off-heap binary) → Rustler Binary<'a> → &[u8]
```

No copying occurs at the BEAM↔Rust boundary. The binary data is referenced directly.

### iodata Usage

The encoder uses Elixir's iodata to build the binary efficiently:

```elixir
IO.iodata_to_binary([
  <<209, 0, version::little-16, flags::little-16, node_count::little-64>>,
  node_binaries
])
```

This avoids intermediate binary allocations.

### Node Count

The `node_count` field in the header allows the Rust side to pre-allocate memory if desired.

---

## Future Extensions

### Flags Field

The 16-bit `flags` field in version 3 header is reserved for:

- Compression indication
- Encryption indication
- Custom extensions

### Additional Opcodes

New opcodes (0x0B+) can be added for custom patch operations without breaking backward compatibility.

### Additional Property Types

New property tags can be added (14, 15, 16, ...) without breaking backward compatibility.

---

## References

- Implementation: `lib/dala/ui/renderer.ex` (functions `encode_tree`, `encode_frame`, `hash_id`)
- NIF declarations: `lib/dala/platform/native.ex` (`set_root_binary/1`, `apply_patches/1`)
- Tests: `test/dala/binary_protocol_test.exs` (Elixir) and `native/dala_nif/src/protocol.rs` (Rust)
- Rust NIF decoder: `native/dala_nif/src/protocol.rs` (fully implemented with 21+ tests)