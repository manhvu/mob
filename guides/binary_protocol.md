# Binary Protocol — Dala UI Render Pipeline

## Overview

Dala's UI render pipeline uses a **custom binary protocol** to transfer UI trees and incremental patches from Elixir (BEAM) to the native side (Rust NIF → SwiftUI/Compose). This replaces the previous JSON-based approach.

### Why Binary Instead of JSON?

| Aspect | JSON (Old) | Binary Protocol (New) |
|--------|-------------|----------------------|
| Encoding | `:json.encode/1` | `Dala.Renderer.encode_tree/1` |
| Decoding | `JSON.parse()` in Rust | Direct binary read in Rust |
| Size | ~200-400 bytes per node | ~50-100 bytes per node |
| Parsing | String parsing overhead | Zero-copy struct reads |
| BEAM boundary | Binary (off-heap) | Binary (off-heap, zero-copy) |

### Key Benefits

1. **Zero-copy at boundary**: Rustler's `Binary<'a>` maps directly to BEAM off-heap binaries
2. **No JSON parsing**: Native side reads structured binary data directly
3. **Compact encoding**: Binary format is 3-5x smaller than JSON
4. **Type-safe**: Well-defined format with versioning support

---

## Binary Format Specification

### Version History

| Version | Used For | Description |
|---------|----------|-------------|
| 1 | Patches | Incremental patch frames |
| 2 | Full Trees | Complete UI tree encoding |

---

## Full Tree Format (Version 2)

Used by `Dala.Renderer.encode_tree/1` and `Dala.Native.set_root_binary/1`.

### Header

```
[u16 version=2][u16 flags][u64 node_count]
```

| Field | Size | Description |
|-------|------|-------------|
| version | 2 bytes | Always `2` (little-endian) |
| flags | 2 bytes | Reserved for future use (currently `0`) |
| node_count | 8 bytes | Total number of nodes in the tree (little-endian) |

### Node Encoding

Each node is encoded as:

```
[u64 id][u8 type][u8 field_count][props...][u32 child_count][u64 child_ids...]
```

#### Node ID (8 bytes)
A 64-bit hashed identifier for the node, computed by `Dala.Renderer.hash_id/1`:

```elixir
defp hash_id(id) do
  id_str = to_string(id)
  lo = :erlang.phash2(id_str, 0xFFFFFFFF)
  hi = :erlang.phash2({id_str, :hi}, 0xFFFFFFFF)
  Bitwise.bor(Bitwise.bsl(hi, 32), lo)
end
```

This ensures stable, deterministic IDs for diffing.

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
| 0 (default) | Unknown types default to 0 |

#### Property Count (1 byte)
Number of properties encoded for this node (0-255).

#### Properties (variable)
Each property is encoded as:

```
[u8 tag][value...]
```

See **Property Encoding** section below.

#### Child Count (4 bytes)
Number of children this node has (little-endian u32).

#### Child IDs (variable)
Array of `child_count × 8 bytes`, each child ID is a u64 (little-endian).

---

## Patch Frame Format (Version 1)

Used by `Dala.Renderer.encode_frame/1` and `Dala.Native.apply_patches/1`.

### Header

```
[u16 version=1][u16 patch_count]
```

| Field | Size | Description |
|-------|------|-------------|
| version | 2 bytes | Always `1` (little-endian) |
| patch_count | 2 bytes | Number of patches in this frame (little-endian) |

### Patch Opcodes

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

Located in `lib/dala/renderer.ex`:

```elixir
# Full tree encoding
Dala.Renderer.encode_tree(%Dala.Node{} = node)

# Patch frame encoding
Dala.Renderer.encode_frame([patch1, patch2, ...])

# Hash function for stable node IDs
Dala.Renderer.hash_id(id)  # returns u64 integer
```

### Rust NIF Side (Decoder)

The Rust NIF (`native/dala_nif/src/`) receives binaries via Rustler:

```rust
#[rustler::nif]
fn set_root_binary(binary: Binary) -> NifResult<Atom> {
    let bytes: &[u8] = binary.as_slice();
    // Parse header: version, flags, node_count
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

binary = Dala.Renderer.encode_tree(node)
# => <<2, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, ...>>
```

### Encoding Patches

```elixir
patches = [
  {:remove, "old_node"},
  {:update_props, "node1", %{text: "Updated"}},
  {:insert, "parent", 0, %Dala.Node{...}}
]

binary = Dala.Renderer.encode_frame(patches)
# => <<1, 0, 3, 0, ...>>
```

### In Render Functions

```elixir
# Dala.Renderer.render/4 now uses binary protocol
def render(tree, platform, nif \\ @default_nif, _transition \\ :none) do
  node = to_node(tree, "root")
  binary = encode_tree(node)
  nif.set_root_binary(binary)  # Instead of nif.set_root(json)
  {:ok, :binary_tree}
end
```

---

## Migration from JSON

### What Changed

| Function | Old (JSON) | New (Binary) |
|----------|-------------|--------------|
| `render/4` | `set_root(json)` | `set_root_binary(binary)` |
| `render_fast/4` | `set_root(json)` | `set_root_binary(binary)` |
| `render_patches/5` | `set_root(json)` for full render | `set_root_binary(binary)` |
| Encoding | `:json.encode/1` | `encode_tree/1` or `encode_frame/1` |

### Backward Compatibility

- `Dala.Native.set_root/1` (JSON) is still available for backward compatibility
- `Dala.Native.set_root_binary/1` is the new preferred method
- The Rust NIF should implement both `set_root` and `set_root_binary`

---

## Testing

Test file: `test/dala/binary_protocol_test.exs`

```elixir
# Example test
test "encodes a simple text node" do
  node = %Node{
    id: "text1",
    type: :text,
    props: %{text: "Hello"},
    children: []
  }

  binary = Renderer.encode_tree(node)
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
  <<version::little-16, flags::little-16, node_count::little-64>>,
  node_binaries
])
```

This avoids intermediate binary allocations.

### Node Count

The `node_count` field in the header allows the Rust side to pre-allocate memory if desired.

---

## Future Extensions

### Flags Field

The 16-bit `flags` field in version 2 header is reserved for:

- Compression indication
- Encryption indication
- Custom extensions

### Additional Property Types

New property tags can be added (13, 14, 15, ...) without breaking backward compatibility.

---

## References

- Implementation: `lib/dala/renderer.ex` (functions `encode_tree`, `encode_frame`, `hash_id`)
- NIF declarations: `lib/dala/native.ex` (`set_root_binary/1`)
- Tests: `test/dala/binary_protocol_test.exs`
- Rust NIF: `native/dala_nif/src/` (decoder implementation needed)
