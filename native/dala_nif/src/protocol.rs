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
