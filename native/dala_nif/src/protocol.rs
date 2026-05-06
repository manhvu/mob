// Binary protocol v2 for Dala patch transmission
// Simplified: no string table, inline strings, layout props in Props
//
// Header:
//   [u16 version=1][u16 patch_count]
//
// Opcodes:
//   0x01 = INSERT   [u8=1][u64 id][u64 parent][u32 index][u8 type][PROPS]
//   0x02 = REMOVE   [u8=2][u64 id]
//   0x03 = UPDATE   [u8=3][u64 id][PROPS]
//
// PROPS format:
//   [u8 field_count]
//     repeat:
//       [u8 tag][value...]
//
// Prop tags:
//   1  = text             [u16 len][bytes...]
//   2  = title            [u16 len][bytes...]
//   3  = color            [u16 len][bytes...]
//   4  = background       [u16 len][bytes...]
//   5  = on_tap           [u64]
//   6  = width            [f32]
//   7  = height           [f32]
//   8  = padding          [f32]
//   9  = flex_grow        [f32]
//   10 = flex_direction   [u8: 0=Column, 1=Row]
//   11 = justify_content  [u8: 0=Start, 1=Center, 2=End, 3=SpaceBetween]
//   12 = align_items      [u8: 0=Start, 1=Center, 2=End, 3=Stretch]

// ── Constants ─────────────────────────────────────────────────────────

pub const VERSION: u16 = 1;

pub const OP_INSERT: u8 = 0x01;
pub const OP_REMOVE: u8 = 0x02;
pub const OP_UPDATE: u8 = 0x03;

// Node type tags (u8)
pub const NODE_COLUMN: u8 = 0;
pub const NODE_ROW: u8 = 1;
pub const NODE_TEXT: u8 = 2;
pub const NODE_BUTTON: u8 = 3;
pub const NODE_IMAGE: u8 = 4;
pub const NODE_SCROLL: u8 = 5;
pub const NODE_WEBVIEW: u8 = 6;

// Prop field tags (u8)
pub const FIELD_TEXT: u8 = 1;
pub const FIELD_TITLE: u8 = 2;
pub const FIELD_COLOR: u8 = 3;
pub const FIELD_BACKGROUND: u8 = 4;
pub const FIELD_ON_TAP: u8 = 5;
pub const FIELD_WIDTH: u8 = 6;
pub const FIELD_HEIGHT: u8 = 7;
pub const FIELD_PADDING: u8 = 8;
pub const FIELD_FLEX_GROW: u8 = 9;
pub const FIELD_FLEX_DIRECTION: u8 = 10;
pub const FIELD_JUSTIFY_CONTENT: u8 = 11;
pub const FIELD_ALIGN_ITEMS: u8 = 12;

// Flex direction values
pub const FLEX_COLUMN: u8 = 0;
pub const FLEX_ROW: u8 = 1;

// Justify content values
pub const JUSTIFY_START: u8 = 0;
pub const JUSTIFY_CENTER: u8 = 1;
pub const JUSTIFY_END: u8 = 2;
pub const JUSTIFY_SPACE_BETWEEN: u8 = 3;

// Align items values
pub const ALIGN_START: u8 = 0;
pub const ALIGN_CENTER: u8 = 1;
pub const ALIGN_END: u8 = 2;
pub const ALIGN_STRETCH: u8 = 3;

// ── Read helpers (little-endian) ──────────────────────────────────────

pub fn read_u8(bytes: &[u8], i: &mut usize) -> u8 {
    let val = bytes[*i];
    *i += 1;
    val
}

pub fn read_u16(bytes: &[u8], i: &mut usize) -> u16 {
    let mut arr = [0u8; 2];
    arr.copy_from_slice(&bytes[*i..*i + 2]);
    *i += 2;
    u16::from_le_bytes(arr)
}

pub fn read_u32(bytes: &[u8], i: &mut usize) -> u32 {
    let mut arr = [0u8; 4];
    arr.copy_from_slice(&bytes[*i..*i + 4]);
    *i += 4;
    u32::from_le_bytes(arr)
}

pub fn read_u64(bytes: &[u8], i: &mut usize) -> u64 {
    let mut arr = [0u8; 8];
    arr.copy_from_slice(&bytes[*i..*i + 8]);
    *i += 8;
    u64::from_le_bytes(arr)
}

pub fn read_f32(bytes: &[u8], i: &mut usize) -> f32 {
    let mut arr = [0u8; 4];
    arr.copy_from_slice(&bytes[*i..*i + 4]);
    *i += 4;
    f32::from_le_bytes(arr)
}

/// Read an inline string: [u16 len][bytes...]
pub fn read_string_inline(bytes: &[u8], i: &mut usize) -> String {
    let len = read_u16(bytes, i) as usize;
    let s = String::from_utf8_lossy(&bytes[*i..*i + len]).into_owned();
    *i += len;
    s
}

// ── Decode ────────────────────────────────────────────────────────────

fn decode_props(bytes: &[u8], i: &mut usize) -> super::tree::Props {
    let field_count = bytes[*i];
    *i += 1;

    let mut props = super::tree::Props::default();

    for _ in 0..field_count {
        let tag = bytes[*i];
        *i += 1;

        match tag {
            FIELD_TEXT => {
                props.text = Some(read_string_inline(bytes, i));
            }
            FIELD_TITLE => {
                props.title = Some(read_string_inline(bytes, i));
            }
            FIELD_COLOR => {
                props.color = Some(read_string_inline(bytes, i));
            }
            FIELD_BACKGROUND => {
                props.background = Some(read_string_inline(bytes, i));
            }
            FIELD_ON_TAP => {
                props.on_tap = Some(read_u64(bytes, i));
            }
            FIELD_WIDTH => {
                props.width = Some(read_f32(bytes, i));
            }
            FIELD_HEIGHT => {
                props.height = Some(read_f32(bytes, i));
            }
            FIELD_PADDING => {
                props.padding = Some(read_f32(bytes, i));
            }
            FIELD_FLEX_GROW => {
                props.flex_grow = Some(read_f32(bytes, i));
            }
            FIELD_FLEX_DIRECTION => {
                props.flex_direction = match bytes[*i] {
                    FLEX_ROW => super::tree::FlexDirection::Row,
                    _ => super::tree::FlexDirection::Column,
                };
                *i += 1;
            }
            FIELD_JUSTIFY_CONTENT => {
                props.justify_content = match bytes[*i] {
                    JUSTIFY_CENTER => super::tree::JustifyContent::Center,
                    JUSTIFY_END => super::tree::JustifyContent::End,
                    JUSTIFY_SPACE_BETWEEN => super::tree::JustifyContent::SpaceBetween,
                    _ => super::tree::JustifyContent::Start,
                };
                *i += 1;
            }
            FIELD_ALIGN_ITEMS => {
                props.align_items = match bytes[*i] {
                    ALIGN_CENTER => super::tree::AlignItems::Center,
                    ALIGN_END => super::tree::AlignItems::End,
                    ALIGN_STRETCH => super::tree::AlignItems::Stretch,
                    _ => super::tree::AlignItems::Start,
                };
                *i += 1;
            }
            _ => {
                eprintln!("[Dala] Unknown prop field tag: {}", tag);
            }
        }
    }

    props
}

/// Decode a node: [id:u64][type:u8][PROPS][children_count:u32][child_ids...]
fn decode_node(bytes: &[u8], i: &mut usize) -> super::tree::Node {
    let id = read_u64(bytes, i);

    let kind = match bytes[*i] {
        NODE_COLUMN => super::tree::NodeKind::Column,
        NODE_ROW => super::tree::NodeKind::Row,
        NODE_TEXT => super::tree::NodeKind::Text,
        NODE_BUTTON => super::tree::NodeKind::Button,
        NODE_IMAGE => super::tree::NodeKind::Image,
        NODE_SCROLL => super::tree::NodeKind::Scroll,
        NODE_WEBVIEW => super::tree::NodeKind::WebView,
        _ => {
            eprintln!("[Dala] Unknown node type: {}", bytes[*i]);
            super::tree::NodeKind::Column
        }
    };
    *i += 1;

    let props = decode_props(bytes, i);

    let children_count = read_u32(bytes, i) as usize;
    let mut children = Vec::with_capacity(children_count);
    for _ in 0..children_count {
        children.push(read_u64(bytes, i));
    }

    super::tree::Node {
        id,
        kind,
        props,
        parent: None,
        children,
        layout: super::tree::Layout::default(),
        dirty_layout: true,
        dirty_paint: true,
    }
}

/// Decode a binary frame and apply patches to the tree.
pub fn decode_and_apply(tree: &mut super::tree::Tree, bytes: &[u8]) {
    // Need at least 4 bytes for header (version + patch_count)
    if bytes.len() < 4 {
        eprintln!("[Dala] Input too short for header: {} bytes", bytes.len());
        return;
    }

    let mut i = 0;

    // Header: [u16 version][u16 patch_count]
    let version = read_u16(bytes, &mut i);
    if version != VERSION {
        eprintln!("[Dala] Unknown protocol version: {}", version);
        return;
    }

    let patch_count = read_u16(bytes, &mut i) as usize;

    for _ in 0..patch_count {
        let opcode = bytes[i];
        i += 1;

        match opcode {
            OP_INSERT => {
                // [u64 id][u64 parent][u32 index][u8 type][PROPS]
                let id = read_u64(bytes, &mut i);
                let parent = read_u64(bytes, &mut i);
                let index = read_u32(bytes, &mut i) as usize;
                let node = decode_node_from_insert(bytes, &mut i, id);
                tree.apply_patch(super::tree::Patch::Insert {
                    parent,
                    index,
                    node,
                });
            }
            OP_REMOVE => {
                let id = read_u64(bytes, &mut i);
                tree.apply_patch(super::tree::Patch::Remove { id });
            }
            OP_UPDATE => {
                let id = read_u64(bytes, &mut i);
                let props = decode_props(bytes, &mut i);
                tree.apply_patch(super::tree::Patch::UpdateProps { id, props });
            }
            _ => {
                eprintln!("[Dala] Unknown opcode: 0x{:02x}", opcode);
                break;
            }
        }
    }
}

/// Decode node fields for INSERT: the id is already read from the wire,
/// so we read [type:u8][PROPS][children_count:u32][child_ids...]
fn decode_node_from_insert(bytes: &[u8], i: &mut usize, id: u64) -> super::tree::Node {
    let kind = match bytes[*i] {
        NODE_COLUMN => super::tree::NodeKind::Column,
        NODE_ROW => super::tree::NodeKind::Row,
        NODE_TEXT => super::tree::NodeKind::Text,
        NODE_BUTTON => super::tree::NodeKind::Button,
        NODE_IMAGE => super::tree::NodeKind::Image,
        NODE_SCROLL => super::tree::NodeKind::Scroll,
        NODE_WEBVIEW => super::tree::NodeKind::WebView,
        _ => {
            eprintln!("[Dala] Unknown node type: {}", bytes[*i]);
            super::tree::NodeKind::Column
        }
    };
    *i += 1;

    let props = decode_props(bytes, i);

    let children_count = read_u32(bytes, i) as usize;
    let mut children = Vec::with_capacity(children_count);
    for _ in 0..children_count {
        children.push(read_u64(bytes, i));
    }

    super::tree::Node {
        id,
        kind,
        props,
        parent: None,
        children,
        layout: super::tree::Layout::default(),
        dirty_layout: true,
        dirty_paint: true,
    }
}

// ── Tests ──────────────────────────────────────────────────
#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::{AlignItems, FlexDirection, JustifyContent, Node, NodeKind, Props, Tree};

    // Helper to create a simple tree for testing
    fn make_tree() -> Tree {
        Tree::new()
    }

    #[test]
    fn test_read_u8() {
        let bytes = vec![0xAB];
        let mut i = 0;
        assert_eq!(read_u8(&bytes, &mut i), 0xAB);
        assert_eq!(i, 1);
    }

    #[test]
    fn test_read_u16_le() {
        let bytes = vec![0x34, 0x12]; // 0x1234 in little-endian
        let mut i = 0;
        assert_eq!(read_u16(&bytes, &mut i), 0x1234);
        assert_eq!(i, 2);
    }

    #[test]
    fn test_read_u32_le() {
        let bytes = vec![0x78, 0x56, 0x34, 0x12]; // 0x12345678
        let mut i = 0;
        assert_eq!(read_u32(&bytes, &mut i), 0x12345678);
        assert_eq!(i, 4);
    }

    #[test]
    fn test_read_u64_le() {
        let bytes = vec![0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01];
        let mut i = 0;
        assert_eq!(read_u64(&bytes, &mut i), 0x0123456789ABCDEF);
        assert_eq!(i, 8);
    }

    #[test]
    fn test_read_f32_le() {
        let bytes = 123.45f32.to_le_bytes();
        let mut i = 0;
        let val = read_f32(&bytes, &mut i);
        assert!((val - 123.45).abs() < 0.01);
        assert_eq!(i, 4);
    }

    #[test]
    fn test_read_string_inline() {
        let mut bytes = vec![];
        let s = "Hello";
        bytes.extend_from_slice(&(s.len() as u16).to_le_bytes());
        bytes.extend_from_slice(s.as_bytes());

        let mut i = 0;
        let result = read_string_inline(&bytes, &mut i);
        assert_eq!(result, "Hello");
        assert_eq!(i, 7); // 2 (len) + 5 (string)
    }

    #[test]
    fn test_decode_remove_patch() {
        // Header: version=1, patch_count=1
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count
        bytes.push(OP_REMOVE); // opcode
        bytes.extend_from_slice(&99u64.to_le_bytes()); // id=99

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Tree should have processed the remove patch
        // (actual verification depends on tree implementation)
    }

    #[test]
    fn test_decode_update_props_patch() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count
        bytes.push(OP_UPDATE); // opcode
        bytes.extend_from_slice(&42u64.to_le_bytes()); // id=42

        // Props: 1 field
        bytes.push(1); // field_count=1
        bytes.push(FIELD_TEXT); // tag=TEXT
        let text = "Updated";
        bytes.extend_from_slice(&(text.len() as u16).to_le_bytes());
        bytes.extend_from_slice(text.as_bytes());

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Tree should have updated props for node 42
    }

    #[test]
    fn test_decode_insert_patch() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count
        bytes.push(OP_INSERT); // opcode
        bytes.extend_from_slice(&100u64.to_le_bytes()); // id=100
        bytes.extend_from_slice(&50u64.to_le_bytes()); // parent=50
        bytes.extend_from_slice(&0u32.to_le_bytes()); // index=0
        bytes.push(NODE_TEXT); // type=TEXT

        // Props: 1 field
        bytes.push(1); // field_count=1
        bytes.push(FIELD_TEXT); // tag=TEXT
        let text = "Hello";
        bytes.extend_from_slice(&(text.len() as u16).to_le_bytes());
        bytes.extend_from_slice(text.as_bytes());

        // Children: count=0
        bytes.extend_from_slice(&0u32.to_le_bytes());

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Tree should have inserted new node
    }

    #[test]
    fn test_decode_multiple_patches() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&2u16.to_le_bytes()); // patch_count=2

        // Patch 1: REMOVE id=10
        bytes.push(OP_REMOVE);
        bytes.extend_from_slice(&10u64.to_le_bytes());

        // Patch 2: UPDATE id=20 with text
        bytes.push(OP_UPDATE);
        bytes.extend_from_slice(&20u64.to_le_bytes());
        bytes.push(1); // field_count=1
        bytes.push(FIELD_TEXT);
        let text = "Updated";
        bytes.extend_from_slice(&(text.len() as u16).to_le_bytes());
        bytes.extend_from_slice(text.as_bytes());

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Tree should have processed both patches
    }

    #[test]
    fn test_decode_props_all_types() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.push(OP_UPDATE);
        bytes.extend_from_slice(&1u64.to_le_bytes());

        // Props with multiple fields
        bytes.push(5); // field_count=5

        // text
        bytes.push(FIELD_TEXT);
        let text = "Hello";
        bytes.extend_from_slice(&(text.len() as u16).to_le_bytes());
        bytes.extend_from_slice(text.as_bytes());

        // width
        bytes.push(FIELD_WIDTH);
        bytes.extend_from_slice(&100.0f32.to_le_bytes());

        // height
        bytes.push(FIELD_HEIGHT);
        bytes.extend_from_slice(&50.0f32.to_le_bytes());

        // padding
        bytes.push(FIELD_PADDING);
        bytes.extend_from_slice(&10.0f32.to_le_bytes());

        // flex_direction (row)
        bytes.push(FIELD_FLEX_DIRECTION);
        bytes.push(FLEX_ROW);

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
    }

    #[test]
    fn test_invalid_version() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&99u16.to_le_bytes()); // invalid version
        bytes.extend_from_slice(&0u16.to_le_bytes());

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Should print error and return without panic
    }

    #[test]
    fn test_empty_patch_list() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&0u16.to_le_bytes()); // patch_count=0

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Should do nothing, no panic
    }

    #[test]
    fn test_deeply_nested_tree_decoding() {
        // Build a patch that simulates a deeply nested tree update
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count=1

        bytes.push(OP_INSERT);
        bytes.extend_from_slice(&1u64.to_le_bytes()); // id
        bytes.extend_from_slice(&0u64.to_le_bytes()); // parent
        bytes.extend_from_slice(&0u32.to_le_bytes()); // index
        bytes.push(NODE_COLUMN); // type

        // Props
        bytes.push(1); // field_count=1
        bytes.push(FIELD_PADDING);
        bytes.extend_from_slice(&5.0f32.to_le_bytes());

        // Children: 4 levels deep
        bytes.extend_from_slice(&4u32.to_le_bytes()); // 4 children
        for i in 1..=4 {
            bytes.extend_from_slice(&(i as u64).to_le_bytes());
        }

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
    }

    #[test]
    fn test_wide_tree_many_children() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count=1

        bytes.push(OP_INSERT);
        bytes.extend_from_slice(&100u64.to_le_bytes()); // id
        bytes.extend_from_slice(&0u64.to_le_bytes()); // parent
        bytes.extend_from_slice(&0u32.to_le_bytes()); // index
        bytes.push(NODE_COLUMN); // type

        // Props: 2 fields
        bytes.push(2);
        bytes.push(FIELD_PADDING);
        bytes.extend_from_slice(&16.0f32.to_le_bytes());
        bytes.push(FIELD_BACKGROUND);
        let bg = "surface";
        bytes.extend_from_slice(&(bg.len() as u16).to_le_bytes());
        bytes.extend_from_slice(bg.as_bytes());

        // 25 children
        bytes.extend_from_slice(&25u32.to_le_bytes());
        for i in 1..=25 {
            bytes.extend_from_slice(&(i as u64).to_le_bytes());
        }

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
    }

    #[test]
    fn test_multiple_patch_types_mixed() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&5u16.to_le_bytes()); // patch_count=5

        // 1. REMOVE
        bytes.push(OP_REMOVE);
        bytes.extend_from_slice(&10u64.to_le_bytes());

        // 2. UPDATE with multiple props
        bytes.push(OP_UPDATE);
        bytes.extend_from_slice(&20u64.to_le_bytes());
        bytes.push(3); // field_count=3
        bytes.push(FIELD_TEXT);
        let text = "Updated text";
        bytes.extend_from_slice(&(text.len() as u16).to_le_bytes());
        bytes.extend_from_slice(text.as_bytes());
        bytes.push(FIELD_WIDTH);
        bytes.extend_from_slice(&200.0f32.to_le_bytes());
        bytes.push(FIELD_HEIGHT);
        bytes.extend_from_slice(&50.0f32.to_le_bytes());

        // 3. INSERT
        bytes.push(OP_INSERT);
        bytes.extend_from_slice(&30u64.to_le_bytes());
        bytes.extend_from_slice(&0u64.to_le_bytes());
        bytes.extend_from_slice(&0u32.to_le_bytes());
        bytes.push(NODE_BUTTON);
        bytes.push(2); // field_count=2
        bytes.push(FIELD_TEXT);
        let btn_text = "Click me";
        bytes.extend_from_slice(&(btn_text.len() as u16).to_le_bytes());
        bytes.extend_from_slice(btn_text.as_bytes());
        bytes.push(FIELD_BACKGROUND);
        let bg = "blue";
        bytes.extend_from_slice(&(bg.len() as u16).to_le_bytes());
        bytes.extend_from_slice(bg.as_bytes());
        bytes.extend_from_slice(&0u32.to_le_bytes()); // no children

        // 4. UPDATE with flex props
        bytes.push(OP_UPDATE);
        bytes.extend_from_slice(&40u64.to_le_bytes());
        bytes.push(3);
        bytes.push(FIELD_FLEX_GROW);
        bytes.extend_from_slice(&1.0f32.to_le_bytes());
        bytes.push(FIELD_FLEX_DIRECTION);
        bytes.push(FLEX_ROW);
        bytes.push(FIELD_JUSTIFY_CONTENT);
        bytes.push(JUSTIFY_CENTER);

        // 5. REMOVE
        bytes.push(OP_REMOVE);
        bytes.extend_from_slice(&50u64.to_le_bytes());

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
    }

    #[test]
    fn test_unicode_text_handling() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count=1

        bytes.push(OP_UPDATE);
        bytes.extend_from_slice(&1u64.to_le_bytes()); // id

        // Props with unicode text (emoji, CJK, accents)
        bytes.push(3); // field_count=3

        bytes.push(FIELD_TEXT);
        let text = "Hello 🎉 你好 안녕하세요 Café";
        bytes.extend_from_slice(&(text.len() as u16).to_le_bytes());
        bytes.extend_from_slice(text.as_bytes());

        bytes.push(FIELD_TITLE);
        let title = "こんにちは";
        bytes.extend_from_slice(&(title.len() as u16).to_le_bytes());
        bytes.extend_from_slice(title.as_bytes());

        bytes.push(FIELD_COLOR);
        let color = "primary";
        bytes.extend_from_slice(&(color.len() as u16).to_le_bytes());
        bytes.extend_from_slice(color.as_bytes());

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
    }

    #[test]
    fn test_rapid_successive_decodes() {
        for i in 1..=10 {
            let mut bytes = vec![];
            bytes.extend_from_slice(&1u16.to_le_bytes()); // version
            bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count=1

            bytes.push(OP_UPDATE);
            bytes.extend_from_slice(&(i as u64).to_le_bytes());
            bytes.push(1); // field_count=1
            bytes.push(FIELD_PADDING);
            bytes.extend_from_slice(&(i as f32).to_le_bytes());

            let mut tree = make_tree();
            decode_and_apply(&mut tree, &bytes);
        }
    }

    #[test]
    fn test_edge_case_max_children() {
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes()); // version
        bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count=1

        bytes.push(OP_INSERT);
        bytes.extend_from_slice(&999u64.to_le_bytes());
        bytes.extend_from_slice(&0u64.to_le_bytes());
        bytes.extend_from_slice(&0u32.to_le_bytes());
        bytes.push(NODE_COLUMN);
        bytes.push(0); // no props

        // 100 children (stress test)
        bytes.extend_from_slice(&100u32.to_le_bytes());
        for i in 0..100 {
            bytes.extend_from_slice(&(i as u64).to_le_bytes());
        }

        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
    }

    #[test]
    fn test_all_node_types() {
        let node_types = [
            (NODE_COLUMN, "Column"),
            (NODE_ROW, "Row"),
            (NODE_TEXT, "Text"),
            (NODE_BUTTON, "Button"),
            (NODE_IMAGE, "Image"),
            (NODE_SCROLL, "Scroll"),
            (NODE_WEBVIEW, "WebView"),
        ];

        for (node_type, _name) in node_types.iter() {
            let mut bytes = vec![];
            bytes.extend_from_slice(&1u16.to_le_bytes()); // version
            bytes.extend_from_slice(&1u16.to_le_bytes()); // patch_count=1

            bytes.push(OP_INSERT);
            bytes.extend_from_slice(&1u64.to_le_bytes());
            bytes.extend_from_slice(&0u64.to_le_bytes());
            bytes.extend_from_slice(&0u32.to_le_bytes());
            bytes.push(*node_type);
            bytes.push(0); // no props
            bytes.extend_from_slice(&0u32.to_le_bytes()); // no children

            let mut tree = make_tree();
            decode_and_apply(&mut tree, &bytes);
        }
    }

    #[test]
    fn test_malformed_input_graceful_handling() {
        // Too short for header
        let bytes = vec![0x01];
        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Should not panic

        // Invalid opcode
        let mut bytes = vec![];
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.push(0xFF); // invalid opcode
        let mut tree = make_tree();
        decode_and_apply(&mut tree, &bytes);
        // Should not panic
    }
}
