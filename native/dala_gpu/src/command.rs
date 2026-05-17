//! Render command types.
//!
//! Commands are submitted from the BEAM/NIF thread via a channel and processed
//! on the dedicated render thread.

/// A single render command in the queue.
#[derive(Debug, Clone, PartialEq)]
pub enum RenderCommand {
    /// Clear the entire framebuffer to a solid color.
    Clear {
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Fill a rectangle with a solid color.
    FillRect {
        /// X coordinate of the top-left corner.
        x: u32,
        /// Y coordinate of the top-left corner.
        y: u32,
        /// Width of the rectangle.
        w: u32,
        /// Height of the rectangle.
        h: u32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Blit a sprite from the texture atlas onto the framebuffer.
    Blit {
        /// Sprite ID in the texture atlas.
        sprite_id: u64,
        /// Destination X coordinate.
        x: u32,
        /// Destination Y coordinate.
        y: u32,
    },

    /// Draw a line between two points using Bresenham's algorithm.
    DrawLine {
        /// Start X coordinate.
        x1: i32,
        /// Start Y coordinate.
        y1: i32,
        /// End X coordinate.
        x2: i32,
        /// End Y coordinate.
        y2: i32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Resize the framebuffer and GPU resources.
    Resize {
        /// New width in pixels.
        width: u32,
        /// New height in pixels.
        height: u32,
    },

    /// Present the current frame: swap buffers, upload texture, render quad.
    Present,

    /// Signal the render thread to shut down.
    Exit,

    /// Dispatch a compute shader.
    DispatchCompute {
        /// Shader source code (MSL for Metal, GLSL for OpenGL ES).
        shader_source: String,
        /// Opaque parameter bytes passed to the shader.
        params: Vec<u8>,
        /// Number of threadgroups to dispatch in (x, y, z).
        workgroup_count: (u32, u32, u32),
    },

    /// Read pixel data back from the GPU.
    ReadPixels {
        /// X coordinate of the region.
        x: u32,
        /// Y coordinate of the region.
        y: u32,
        /// Width of the region.
        w: u32,
        /// Height of the region.
        h: u32,
    },

    /// Copy data between GPU buffers.
    CopyBuffer {
        /// Source buffer ID.
        src: u32,
        /// Destination buffer ID.
        dst: u32,
        /// Number of bytes to copy.
        size: u32,
    },

    /// Load or hot-reload a shader.
    LoadShader {
        /// Shader name for lookup.
        name: String,
        /// Shader source code.
        source: String,
    },

    /// Set a uniform value on the current shader pipeline.
    SetUniform {
        /// Uniform name.
        name: String,
        /// Raw uniform data.
        data: Vec<u8>,
    },

    /// Load a sprite into the texture atlas.
    LoadSprite {
        /// Unique sprite ID.
        id: u64,
        /// Sprite width in pixels.
        w: u32,
        /// Sprite height in pixels.
        h: u32,
        /// RGBA8888 pixel data (w * h * 4 bytes).
        data: Vec<u8>,
    },

    /// Remove a sprite from the texture atlas.
    RemoveSprite {
        /// Sprite ID to remove.
        id: u64,
    },

    /// Load an image into the GPU texture pool.
    LoadImage {
        /// Unique image ID.
        id: u64,
        /// Image width in pixels.
        w: u32,
        /// Image height in pixels.
        h: u32,
        /// RGBA8888 pixel data (w * h * 4 bytes).
        data: Vec<u8>,
    },

    /// Remove an image from the GPU texture pool.
    RemoveImage {
        /// Image ID to remove.
        id: u64,
    },

    /// Blit a loaded image texture onto the framebuffer.
    ImageBlit {
        /// Image ID in the texture pool.
        image_id: u64,
        /// Destination X coordinate.
        x: i32,
        /// Destination Y coordinate.
        y: i32,
        /// Destination width (for scaling).
        w: u32,
        /// Destination height (for scaling).
        h: u32,
    },

    /// Draw a circle outline.
    DrawCircle {
        /// Center X coordinate.
        cx: i32,
        /// Center Y coordinate.
        cy: i32,
        /// Radius in pixels.
        radius: u32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Fill a circle.
    FillCircle {
        /// Center X coordinate.
        cx: i32,
        /// Center Y coordinate.
        cy: i32,
        /// Radius in pixels.
        radius: u32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Draw a triangle outline from three points.
    DrawTriangle {
        /// First point X.
        x1: i32,
        /// First point Y.
        y1: i32,
        /// Second point X.
        x2: i32,
        /// Second point Y.
        y2: i32,
        /// Third point X.
        x3: i32,
        /// Third point Y.
        y3: i32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Fill a triangle.
    FillTriangle {
        /// First point X.
        x1: i32,
        /// First point Y.
        y1: i32,
        /// Second point X.
        x2: i32,
        /// Second point Y.
        y2: i32,
        /// Third point X.
        x3: i32,
        /// Third point Y.
        y3: i32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Draw a rounded rectangle outline.
    DrawRoundRect {
        /// X coordinate of the top-left corner.
        x: u32,
        /// Y coordinate of the top-left corner.
        y: u32,
        /// Width.
        w: u32,
        /// Height.
        h: u32,
        /// Corner radius in pixels.
        radius: u32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Fill a rounded rectangle.
    FillRoundRect {
        /// X coordinate of the top-left corner.
        x: u32,
        /// Y coordinate of the top-left corner.
        y: u32,
        /// Width.
        w: u32,
        /// Height.
        h: u32,
        /// Corner radius in pixels.
        radius: u32,
        /// RGBA color components.
        color: [u8; 4],
    },

    /// Set the clipping rectangle.
    SetClip {
        /// X coordinate of the clip region.
        x: u32,
        /// Y coordinate of the clip region.
        y: u32,
        /// Width of the clip region.
        w: u32,
        /// Height of the clip region.
        h: u32,
        /// Whether clipping is enabled.
        enabled: bool,
    },

    /// Reset the clipping region to the full framebuffer.
    ResetClip,

    /// Batch command: execute multiple commands atomically.
    /// The inner commands are encoded as a concatenated binary blob.
    Batch {
        /// Number of commands in the batch.
        count: u32,
        /// Concatenated binary-encoded commands.
        data: Vec<u8>,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dispatch_compute_roundtrip() {
        let cmd = RenderCommand::DispatchCompute {
            shader_source: "kernel void add()".to_string(),
            params: vec![1, 2, 3],
            workgroup_count: (8, 4, 1),
        };
        match cmd {
            RenderCommand::DispatchCompute {
                ref shader_source,
                ref params,
                workgroup_count,
            } => {
                assert_eq!(shader_source, "kernel void add()");
                assert_eq!(params, &vec![1, 2, 3]);
                assert_eq!(workgroup_count, (8, 4, 1));
            }
            _ => panic!("expected DispatchCompute"),
        }
    }

    #[test]
    fn test_read_pixels_command() {
        let cmd = RenderCommand::ReadPixels {
            x: 10,
            y: 20,
            w: 100,
            h: 200,
        };
        match cmd {
            RenderCommand::ReadPixels { x, y, w, h } => {
                assert_eq!(x, 10);
                assert_eq!(y, 20);
                assert_eq!(w, 100);
                assert_eq!(h, 200);
            }
            _ => panic!("expected ReadPixels"),
        }
    }

    #[test]
    fn test_copy_buffer_command() {
        let cmd = RenderCommand::CopyBuffer {
            src: 1,
            dst: 2,
            size: 1024,
        };
        match cmd {
            RenderCommand::CopyBuffer { src, dst, size } => {
                assert_eq!(src, 1);
                assert_eq!(dst, 2);
                assert_eq!(size, 1024);
            }
            _ => panic!("expected CopyBuffer"),
        }
    }

    #[test]
    fn test_load_shader_command() {
        let cmd = RenderCommand::LoadShader {
            name: "blur".to_string(),
            source: "void main() {}".to_string(),
        };
        match cmd {
            RenderCommand::LoadShader {
                ref name,
                ref source,
            } => {
                assert_eq!(name, "blur");
                assert_eq!(source, "void main() {}");
            }
            _ => panic!("expected LoadShader"),
        }
    }

    #[test]
    fn test_set_uniform_command() {
        let cmd = RenderCommand::SetUniform {
            name: "color".to_string(),
            data: vec![255, 0, 0, 255],
        };
        match cmd {
            RenderCommand::SetUniform { ref name, ref data } => {
                assert_eq!(name, "color");
                assert_eq!(data, &vec![255, 0, 0, 255]);
            }
            _ => panic!("expected SetUniform"),
        }
    }

    #[test]
    fn test_load_sprite_command() {
        let cmd = RenderCommand::LoadSprite {
            id: 42,
            w: 32,
            h: 32,
            data: vec![255u8; 32 * 32 * 4],
        };
        match cmd {
            RenderCommand::LoadSprite { id, w, h, ref data } => {
                assert_eq!(id, 42);
                assert_eq!(w, 32);
                assert_eq!(h, 32);
                assert_eq!(data.len(), 32 * 32 * 4);
            }
            _ => panic!("expected LoadSprite"),
        }
    }

    #[test]
    fn test_remove_sprite_command() {
        let cmd = RenderCommand::RemoveSprite { id: 42 };
        match cmd {
            RenderCommand::RemoveSprite { id } => assert_eq!(id, 42),
            _ => panic!("expected RemoveSprite"),
        }
    }
}
