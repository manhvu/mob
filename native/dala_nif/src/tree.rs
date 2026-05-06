// Patch-based rendering structures

use std::collections::HashMap;
use std::hash::{Hash, Hasher};

// NodeId - using u64 for cheap, stable identity
pub type NodeId = u64;

// NodeKind - represents the type of UI node
#[derive(Debug, Clone, PartialEq)]
pub enum NodeKind {
    Column,
    Row,
    Text,
    Button,
    Image,
    Scroll,
    WebView,
}

// FlexDirection
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum FlexDirection {
    Row,
    Column,
}

impl Default for FlexDirection {
    fn default() -> Self {
        FlexDirection::Column
    }
}

// JustifyContent
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum JustifyContent {
    Start,
    Center,
    End,
    SpaceBetween,
}

impl Default for JustifyContent {
    fn default() -> Self {
        JustifyContent::Start
    }
}

// AlignItems
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AlignItems {
    Start,
    Center,
    End,
    Stretch,
}

impl Default for AlignItems {
    fn default() -> Self {
        AlignItems::Start
    }
}

// Constraints for layout
#[derive(Clone, Copy)]
pub struct Constraints {
    pub max_width: f32,
    pub max_height: f32,
}

// Props - all visual, content, and layout properties in one struct
#[derive(Debug, Clone, PartialEq)]
pub struct Props {
    // Content props
    pub text: Option<String>,
    pub title: Option<String>,
    pub color: Option<String>,
    pub background: Option<String>,
    pub on_tap: Option<u64>,
    // Layout props (formerly in Style)
    pub width: Option<f32>,
    pub height: Option<f32>,
    pub padding: Option<f32>,
    pub flex_grow: Option<f32>,
    pub flex_direction: FlexDirection,
    pub justify_content: JustifyContent,
    pub align_items: AlignItems,
}

impl Default for Props {
    fn default() -> Self {
        Props {
            text: None,
            title: None,
            color: None,
            background: None,
            on_tap: None,
            width: None,
            height: None,
            padding: None,
            flex_grow: None,
            flex_direction: FlexDirection::default(),
            justify_content: JustifyContent::default(),
            align_items: AlignItems::default(),
        }
    }
}

impl Props {
    /// Resolve flex_direction with a default fallback
    pub fn flex_direction(&self) -> FlexDirection {
        self.flex_direction
    }

    /// Resolve justify_content with a default fallback
    pub fn justify_content(&self) -> JustifyContent {
        self.justify_content
    }

    /// Resolve align_items with a default fallback
    pub fn align_items(&self) -> AlignItems {
        self.align_items
    }

    /// Resolve flex_grow, defaulting to 0.0
    pub fn flex_grow_val(&self) -> f32 {
        self.flex_grow.unwrap_or(0.0)
    }

    /// Resolve padding, defaulting to 0.0
    pub fn padding_val(&self) -> f32 {
        self.padding.unwrap_or(0.0)
    }
}

// Layout - cached layout information
#[derive(Debug, Clone, Copy, Default)]
pub struct Layout {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

// Node - the main UI tree node
#[derive(Debug, Clone)]
pub struct Node {
    pub id: NodeId,
    pub kind: NodeKind,
    pub props: Props,
    pub parent: Option<NodeId>,
    pub children: Vec<NodeId>,
    pub layout: Layout,
    pub dirty_layout: bool,
    pub dirty_paint: bool,
}

// Patch - represents a change to apply to the tree
#[derive(Debug, Clone)]
pub enum Patch {
    Insert {
        parent: NodeId,
        index: usize,
        node: Node,
    },
    Remove {
        id: NodeId,
    },
    UpdateProps {
        id: NodeId,
        props: Props,
    },
}

// Tree - the retained UI tree
pub struct Tree {
    pub nodes: HashMap<NodeId, Node>,
    pub root: Option<NodeId>,
    pub dirty_layout: Vec<NodeId>,
    pub dirty_paint: Vec<NodeId>,
}

impl Tree {
    pub fn new() -> Self {
        Tree {
            nodes: HashMap::new(),
            root: None,
            dirty_layout: Vec::new(),
            dirty_paint: Vec::new(),
        }
    }

    // Apply a list of patches
    pub fn apply_patches(&mut self, patches: Vec<Patch>) {
        for patch in patches {
            self.apply_patch(patch);
        }

        self.recompute_layout();
        self.repaint();
    }

    // Apply a single patch
    pub fn apply_patch(&mut self, patch: Patch) {
        match patch {
            Patch::Insert {
                parent,
                index,
                node,
            } => {
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

    // Insert a new node
    fn insert(&mut self, parent_id: NodeId, index: usize, mut node: Node) {
        let id = node.id;

        node.parent = Some(parent_id);
        node.dirty_layout = true;
        node.dirty_paint = true;

        self.nodes.insert(id, node);

        if let Some(parent) = self.nodes.get_mut(&parent_id) {
            if index <= parent.children.len() {
                parent.children.insert(index, id);
            } else {
                parent.children.push(id);
            }
        }

        self.mark_dirty_layout(parent_id);
    }

    // Remove a node and its subtree
    fn remove(&mut self, id: NodeId) {
        if let Some(node) = self.nodes.remove(&id) {
            // Remove from parent's children
            if let Some(parent_id) = node.parent {
                if let Some(parent) = self.nodes.get_mut(&parent_id) {
                    parent.children.retain(|&c| c != id);
                    self.mark_dirty_layout(parent_id);
                }
            }

            // Recursively remove children
            for child_id in node.children {
                self.remove(child_id);
            }
        }
    }

    // Update props on an existing node
    fn update_props(&mut self, id: NodeId, new_props: Props) {
        if let Some(node) = self.nodes.get_mut(&id) {
            if node.props != new_props {
                node.props = new_props;
                node.dirty_layout = true;
                node.dirty_paint = true;
                self.mark_dirty_layout(id);
            }
        }
    }

    // Mark a node as dirty (needs layout recalculation)
    fn mark_dirty_layout(&mut self, id: NodeId) {
        if !self.dirty_layout.contains(&id) {
            self.dirty_layout.push(id);

            // Mark parent as dirty too
            if let Some(node) = self.nodes.get(&id) {
                if let Some(parent_id) = node.parent {
                    self.mark_dirty_layout(parent_id);
                }
            }
        }
    }

    // Recompute layout for dirty nodes
    fn recompute_layout(&mut self) {
        if let Some(root) = self.root {
            let constraints = Constraints {
                max_width: 800.0,
                max_height: 600.0,
            };

            self.layout_node(root, constraints);
        }
    }

    // Layout a single node
    fn layout_node(&mut self, id: NodeId, constraints: Constraints) -> Layout {
        let (flex_direction, children, _kind) = {
            if let Some(node) = self.nodes.get(&id) {
                (
                    node.props.flex_direction(),
                    node.children.clone(),
                    node.kind.clone(),
                )
            } else {
                return Layout::default();
            }
        };

        // Check if node is dirty
        if let Some(node) = self.nodes.get(&id) {
            if !node.dirty_layout && node.layout.width > 0.0 {
                return node.layout;
            }
        }

        if children.is_empty() {
            return self.layout_leaf(id, constraints);
        }

        match flex_direction {
            FlexDirection::Column => self.layout_column(id, constraints),
            FlexDirection::Row => self.layout_row(id, constraints),
        }
    }

    // Layout for leaf nodes (no children)
    fn layout_leaf(&mut self, id: NodeId, constraints: Constraints) -> Layout {
        let node = self.nodes.get_mut(&id).unwrap();

        let width = node.props.width.unwrap_or(constraints.max_width);
        let height = node.props.height.unwrap_or(20.0);

        node.layout.width = width;
        node.layout.height = height;

        node.dirty_layout = false;
        node.layout
    }

    // Column layout (main axis: Y)
    fn layout_column(&mut self, id: NodeId, constraints: Constraints) -> Layout {
        let (flex_direction, justify_content, align_items, padding, children) = {
            let node = self.nodes.get(&id).unwrap();
            (
                node.props.flex_direction(),
                node.props.justify_content(),
                node.props.align_items(),
                node.props.padding_val(),
                node.children.clone(),
            )
        };

        // flex_direction is Column here by caller convention, but read from props
        let _ = flex_direction;
        let inner_width = constraints.max_width - padding * 2.0;

        // 1. First pass: measure children
        let mut total_fixed_height = 0.0;
        let mut total_flex = 0.0;

        let mut child_layouts: Vec<(NodeId, Option<Layout>)> = Vec::new();

        for child_id in &children {
            let child = self.nodes.get(child_id).unwrap();

            if child.props.flex_grow_val() > 0.0 {
                total_flex += child.props.flex_grow_val();
                child_layouts.push((*child_id, None));
            } else {
                let layout = self.layout_node(
                    *child_id,
                    Constraints {
                        max_width: inner_width,
                        max_height: constraints.max_height,
                    },
                );
                total_fixed_height += layout.height;
                child_layouts.push((*child_id, Some(layout)));
            }
        }

        // 2. Distribute remaining space
        let remaining = (constraints.max_height - total_fixed_height - padding * 2.0).max(0.0);

        for (child_id, layout_opt) in &mut child_layouts {
            if layout_opt.is_none() {
                let child = self.nodes.get(child_id).unwrap();
                let flex = child.props.flex_grow_val();

                let height = if total_flex > 0.0 {
                    remaining * (flex / total_flex)
                } else {
                    0.0
                };

                let layout = self.layout_node(
                    *child_id,
                    Constraints {
                        max_width: inner_width,
                        max_height: height,
                    },
                );

                *layout_opt = Some(layout);
            }
        }

        // 3. Position children (justify_content)
        let total_height: f32 = child_layouts.iter().map(|(_, l)| l.unwrap().height).sum();

        let mut y = padding;

        let gap = match justify_content {
            JustifyContent::Start => 0.0,
            JustifyContent::End => constraints.max_height - total_height - padding * 2.0,
            JustifyContent::Center => (constraints.max_height - total_height) / 2.0,
            JustifyContent::SpaceBetween => {
                if children.len() > 1 {
                    (constraints.max_height - total_height - padding * 2.0)
                        / (children.len() - 1) as f32
                } else {
                    0.0
                }
            }
        };

        // 4. Apply positions + align_items
        for (i, (child_id, layout_opt)) in child_layouts.iter().enumerate() {
            let mut layout = layout_opt.unwrap();

            // align_items (cross axis)
            match align_items {
                AlignItems::Start => layout.x = padding,
                AlignItems::Center => layout.x = (constraints.max_width - layout.width) / 2.0,
                AlignItems::End => layout.x = constraints.max_width - layout.width - padding,
                AlignItems::Stretch => {
                    layout.x = padding;
                    layout.width = inner_width;
                }
            }

            layout.y = y;

            let child = self.nodes.get_mut(child_id).unwrap();
            child.layout = layout;
            child.dirty_layout = false;
            child.dirty_paint = true;

            y += layout.height;

            if matches!(justify_content, JustifyContent::SpaceBetween) {
                y += gap;
            } else if i == 0 {
                y += gap;
            }
        }

        // 5. Set own layout
        let node = self.nodes.get_mut(&id).unwrap();
        node.layout.width = constraints.max_width;
        node.layout.height = constraints.max_height;

        node.layout
    }

    // Row layout (main axis: X)
    fn layout_row(&mut self, id: NodeId, constraints: Constraints) -> Layout {
        let (flex_direction, justify_content, align_items, padding, children) = {
            let node = self.nodes.get(&id).unwrap();
            (
                node.props.flex_direction(),
                node.props.justify_content(),
                node.props.align_items(),
                node.props.padding_val(),
                node.children.clone(),
            )
        };

        let _ = flex_direction;
        let inner_height = constraints.max_height - padding * 2.0;

        // 1. First pass: measure children
        let mut total_fixed_width = 0.0;
        let mut total_flex = 0.0;

        let mut child_layouts: Vec<(NodeId, Option<Layout>)> = Vec::new();

        for child_id in &children {
            let child = self.nodes.get(child_id).unwrap();

            if child.props.flex_grow_val() > 0.0 {
                total_flex += child.props.flex_grow_val();
                child_layouts.push((*child_id, None));
            } else {
                let layout = self.layout_node(
                    *child_id,
                    Constraints {
                        max_width: constraints.max_width,
                        max_height: inner_height,
                    },
                );
                total_fixed_width += layout.width;
                child_layouts.push((*child_id, Some(layout)));
            }
        }

        // 2. Distribute remaining space
        let remaining = (constraints.max_width - total_fixed_width - padding * 2.0).max(0.0);

        for (child_id, layout_opt) in &mut child_layouts {
            if layout_opt.is_none() {
                let child = self.nodes.get(child_id).unwrap();
                let flex = child.props.flex_grow_val();

                let width = if total_flex > 0.0 {
                    remaining * (flex / total_flex)
                } else {
                    0.0
                };

                let layout = self.layout_node(
                    *child_id,
                    Constraints {
                        max_width: width,
                        max_height: inner_height,
                    },
                );

                *layout_opt = Some(layout);
            }
        }

        // 3. Position children (justify_content)
        let total_width: f32 = child_layouts.iter().map(|(_, l)| l.unwrap().width).sum();

        let mut x = padding;

        let gap = match justify_content {
            JustifyContent::Start => 0.0,
            JustifyContent::End => constraints.max_width - total_width - padding * 2.0,
            JustifyContent::Center => (constraints.max_width - total_width) / 2.0,
            JustifyContent::SpaceBetween => {
                if children.len() > 1 {
                    (constraints.max_width - total_width - padding * 2.0)
                        / (children.len() - 1) as f32
                } else {
                    0.0
                }
            }
        };

        // 4. Apply positions + align_items
        for (i, (child_id, layout_opt)) in child_layouts.iter().enumerate() {
            let mut layout = layout_opt.unwrap();

            // align_items (cross axis)
            match align_items {
                AlignItems::Start => layout.y = padding,
                AlignItems::Center => layout.y = (constraints.max_height - layout.height) / 2.0,
                AlignItems::End => layout.y = constraints.max_height - layout.height - padding,
                AlignItems::Stretch => {
                    layout.y = padding;
                    layout.height = inner_height;
                }
            }

            layout.x = x;

            let child = self.nodes.get_mut(child_id).unwrap();
            child.layout = layout;
            child.dirty_layout = false;
            child.dirty_paint = true;

            x += layout.width;

            if matches!(justify_content, JustifyContent::SpaceBetween) {
                x += gap;
            } else if i == 0 {
                x += gap;
            }
        }

        // 5. Set own layout
        let node = self.nodes.get_mut(&id).unwrap();
        node.layout.width = constraints.max_width;
        node.layout.height = constraints.max_height;

        node.layout
    }

    // Repaint dirty nodes
    fn repaint(&mut self) {
        let dirty_nodes: Vec<(NodeId, NodeKind, Layout)> = self
            .nodes
            .iter()
            .filter(|(_, node)| node.dirty_paint)
            .map(|(id, node)| (*id, node.kind.clone(), node.layout.clone()))
            .collect();

        for (id, kind, layout) in dirty_nodes {
            Self::draw_node_static(&kind, &layout);
            if let Some(node) = self.nodes.get_mut(&id) {
                node.dirty_paint = false;
            }
        }
    }

    // Draw a single node (static, no self borrow)
    fn draw_node_static(kind: &NodeKind, layout: &Layout) {
        match kind {
            NodeKind::Text => {
                println!("Draw TEXT at ({}, {})", layout.x, layout.y);
            }
            NodeKind::Button => {
                println!("Draw BUTTON at ({}, {})", layout.x, layout.y);
            }
            NodeKind::Column | NodeKind::Row => {
                // Container nodes don't draw anything themselves
            }
            _ => {
                println!("Draw {:?} at ({}, {})", kind, layout.x, layout.y);
            }
        }
    }
}

// Helper to convert Elixir-style ID to NodeId (u64)
pub fn hash_id(id: &str) -> NodeId {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    id.hash(&mut hasher);
    hasher.finish()
}
