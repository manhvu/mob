//! Dala GPU Rendering Runtime
//!
//! Provides a CPU-side framebuffer with GPU texture upload and fullscreen quad
//! rendering. Render commands are submitted from the BEAM/NIF thread and processed
//! on a dedicated render thread.
//!
//! Architecture:
//! ```text
//! Elixir/Dala → Render Commands → Rust Render Runtime → GPU API → Texture → Fullscreen Quad
//! ```

mod atlas;
mod command;
mod framebuffer;
mod nif;
mod renderer;
mod sprite;

pub use atlas::TextureAtlas;
pub use command::RenderCommand;
pub use framebuffer::FrameBuffer;
pub use renderer::{Backend, Renderer};

use crossbeam_channel::{bounded, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;

/// The main GPU renderer handle.
///
/// Owns a dedicated render thread that processes commands from a channel,
/// updates a CPU-side framebuffer, uploads it as a GPU texture, and renders
/// a fullscreen quad.
pub struct GpuRenderer {
    /// Channel sender for submitting render commands from the NIF/BEAM thread.
    cmd_tx: Sender<RenderCommand>,
    /// Shared CPU-side double-buffered framebuffers.
    buffers: Arc<Mutex<DoubleBuffer>>,
    /// Join handle for the render thread (stored so we can join on drop).
    _thread: Option<thread::JoinHandle<()>>,
}

/// Double-buffered framebuffers: back buffer is written to, front buffer is
/// uploaded to the GPU.
struct DoubleBuffer {
    /// Index of the front buffer (currently being uploaded / displayed).
    front: usize,
    /// The two framebuffer slots.
    slots: [FrameBuffer; 2],
}

impl DoubleBuffer {
    fn new(width: u32, height: u32) -> Self {
        Self {
            front: 0,
            slots: [
                FrameBuffer::new(width, height),
                FrameBuffer::new(width, height),
            ],
        }
    }

    /// Get a mutable reference to the back buffer.
    fn back_mut(&mut self) -> &mut FrameBuffer {
        &mut self.slots[1 - self.front]
    }

    /// Get a reference to the front buffer (the one being displayed).
    fn front(&self) -> &FrameBuffer {
        &self.slots[self.front]
    }

    /// Swap front and back buffers.
    fn swap(&mut self) {
        self.front = 1 - self.front;
    }
}

impl GpuRenderer {
    /// Create a new GPU renderer with the given dimensions.
    ///
    /// Spawns a dedicated render thread. The CPU-side framebuffer is accessible
    /// via `framebuffer()` for NIF-level pixel operations.
    pub fn new(width: u32, height: u32) -> Self {
        let (cmd_tx, cmd_rx): (Sender<RenderCommand>, Receiver<RenderCommand>) = bounded(1024);
        let buffers = Arc::new(Mutex::new(DoubleBuffer::new(width, height)));
        let buffers_clone = Arc::clone(&buffers);

        let thread = thread::Builder::new()
            .name("dala-gpu-render".into())
            .spawn(move || {
                render_thread(cmd_rx, buffers_clone, width, height);
            })
            .expect("failed to spawn Dala GPU render thread");

        Self {
            cmd_tx,
            buffers,
            _thread: Some(thread),
        }
    }

    /// Submit a render command to the render thread.
    ///
    /// Non-blocking; returns immediately after sending.
    pub fn submit_command(&self, cmd: RenderCommand) {
        // Best-effort: if the channel is full we drop the command rather than block.
        let _ = self.cmd_tx.try_send(cmd);
    }

    /// Submit all pending commands and present the frame.
    pub fn present(&self) {
        self.submit_command(RenderCommand::Present);
    }

    /// Resize the framebuffer and GPU resources.
    pub fn resize(&self, width: u32, height: u32) {
        self.submit_command(RenderCommand::Resize { width, height });
    }

    /// Copy the front buffer's pixel data into a new Vec.
    ///
    /// This is the safe way to access pixel data from the NIF thread.
    /// The front buffer is the one currently being displayed; the render thread
    /// only writes to the back buffer until the next Present swaps them.
    pub fn framebuffer_pixels(&self) -> Vec<u8> {
        let buf = self.buffers.lock().unwrap();
        buf.front().pixel_data()
    }

    /// Return a raw pointer to the front buffer's pixel data.
    ///
    /// Valid until the next `present()` call swaps buffers.
    /// Use `pixel_len()` to know the buffer size.
    pub fn pixel_ptr(&self) -> *const u8 {
        let buf = self.buffers.lock().unwrap();
        buf.front().pixel_ptr()
    }

    /// Return the byte length of the front buffer's pixel data.
    pub fn pixel_len(&self) -> usize {
        let buf = self.buffers.lock().unwrap();
        buf.front().pixel_len()
    }

    /// Lock the back buffer and apply a mutation function.
    ///
    /// This allows the NIF layer to directly draw into the back buffer
    /// before the render thread processes the next frame.
    pub fn with_back_buffer<F, R>(&self, f: F) -> R
    where
        F: FnOnce(&mut FrameBuffer) -> R,
    {
        let mut buf = self.buffers.lock().unwrap();
        f(buf.back_mut())
    }
}

impl Drop for GpuRenderer {
    fn drop(&mut self) {
        // Send Exit command to stop the render thread.
        let _ = self.cmd_tx.send(RenderCommand::Exit);
        if let Some(handle) = self._thread.take() {
            let _ = handle.join();
        }
    }
}

/// The render thread's main loop.
fn render_thread(
    cmd_rx: Receiver<RenderCommand>,
    buffers: Arc<Mutex<DoubleBuffer>>,
    width: u32,
    height: u32,
) {
    let mut gpu = renderer::create_backend(width, height);

    loop {
        // Batch-receive commands until we hit Present or Exit.
        match cmd_rx.recv() {
            Ok(RenderCommand::Exit) => break,
            Ok(RenderCommand::Present) => {
                // Swap buffers: the back buffer becomes the front.
                {
                    let mut buf = buffers.lock().unwrap();
                    buf.swap();
                }
                // Upload front buffer to GPU and render.
                let pixel_data = {
                    let buf = buffers.lock().unwrap();
                    // Copy pixel data while holding the lock.
                    buf.front().pixel_data()
                };
                gpu.update_texture(&pixel_data);
                gpu.render();
                gpu.present();
            }
            Ok(cmd) => {
                // Mutate the back buffer.
                let mut buf = buffers.lock().unwrap();
                apply_command(buf.back_mut(), &cmd, &mut *gpu);
            }
            Err(_) => break, // Channel closed, exit.
        }

        // Drain any additional pending commands (non-blocking).
        while let Ok(cmd) = cmd_rx.try_recv() {
            match cmd {
                RenderCommand::Exit => {
                    let _ = gpu;
                    return;
                }
                RenderCommand::Present => {
                    {
                        let mut buf = buffers.lock().unwrap();
                        buf.swap();
                    }
                    let pixel_data = {
                        let buf = buffers.lock().unwrap();
                        buf.front().pixel_data()
                    };
                    gpu.update_texture(&pixel_data);
                    gpu.render();
                    gpu.present();
                    break;
                }
                _ => {
                    let mut buf = buffers.lock().unwrap();
                    apply_command(buf.back_mut(), &cmd, &mut *gpu);
                }
            }
        }
    }
}

/// Apply a single render command to the back buffer and GPU backend.
fn apply_command(buf: &mut FrameBuffer, cmd: &RenderCommand, gpu: &mut dyn Renderer) {
    match *cmd {
        RenderCommand::Clear { color } => {
            buf.clear(color);
        }
        RenderCommand::FillRect { x, y, w, h, color } => {
            buf.fill_rect(x, y, w, h, color);
        }
        RenderCommand::Blit { sprite_id, x, y } => {
            // Sprite blitting requires atlas lookup — handled at a higher level.
            // For now, this is a placeholder that the NIF layer can implement
            // by writing directly to the back buffer.
            let _ = (sprite_id, x, y);
        }
        RenderCommand::DrawLine {
            x1,
            y1,
            x2,
            y2,
            color,
        } => {
            buf.draw_line(x1, y1, x2, y2, color);
        }
        RenderCommand::Resize { width, height } => {
            buf.resize(width, height);
            gpu.resize(width, height);
        }
        RenderCommand::Present | RenderCommand::Exit => {
            // These are handled in the main loop, not here.
        }
        RenderCommand::DispatchCompute {
            ref shader_source,
            ref params,
            workgroup_count,
        } => {
            gpu.dispatch_compute(shader_source, params);
            let _ = workgroup_count;
        }
        RenderCommand::ReadPixels { x, y, w, h } => {
            let pixel_count = (w * h * 4) as usize;
            let mut data = vec![0u8; pixel_count];
            gpu.read_pixels(&mut data);
            let _ = (x, y);
        }
        RenderCommand::CopyBuffer { src, dst, size } => {
            let _ = (src, dst, size);
        }
        RenderCommand::LoadShader {
            ref name,
            ref source,
        } => {
            let _ = (name, source);
        }
        RenderCommand::SetUniform { ref name, ref data } => {
            let _ = (name, data);
        }
        RenderCommand::LoadSprite { id, w, h, ref data } => {
            let _ = (id, w, h, data);
        }
        RenderCommand::RemoveSprite { id } => {
            let _ = id;
        }
        RenderCommand::LoadImage { id, w, h, ref data } => {
            let _ = (id, w, h, data);
        }
        RenderCommand::RemoveImage { id } => {
            let _ = id;
        }
        RenderCommand::ImageBlit {
            image_id,
            x,
            y,
            w,
            h,
        } => {
            let _ = (image_id, x, y, w, h);
        }
        RenderCommand::DrawCircle {
            cx,
            cy,
            radius,
            color,
        } => {
            buf.draw_circle(cx, cy, radius, color);
        }
        RenderCommand::FillCircle {
            cx,
            cy,
            radius,
            color,
        } => {
            buf.fill_circle(cx, cy, radius, color);
        }
        RenderCommand::DrawTriangle {
            x1,
            y1,
            x2,
            y2,
            x3,
            y3,
            color,
        } => {
            buf.draw_triangle(x1, y1, x2, y2, x3, y3, color);
        }
        RenderCommand::FillTriangle {
            x1,
            y1,
            x2,
            y2,
            x3,
            y3,
            color,
        } => {
            buf.fill_triangle(x1, y1, x2, y2, x3, y3, color);
        }
        RenderCommand::DrawRoundRect {
            x,
            y,
            w,
            h,
            radius,
            color,
        } => {
            buf.draw_round_rect(x, y, w, h, radius, color);
        }
        RenderCommand::FillRoundRect {
            x,
            y,
            w,
            h,
            radius,
            color,
        } => {
            buf.fill_round_rect(x, y, w, h, radius, color);
        }
        RenderCommand::SetClip {
            x,
            y,
            w,
            h,
            enabled,
        } => {
            let _ = (x, y, w, h, enabled);
        }
        RenderCommand::ResetClip => {
            // no-op on CPU framebuffer
        }
        RenderCommand::Batch { count, ref data } => {
            let _ = (count, data);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gpu_renderer_creation() {
        let renderer = GpuRenderer::new(640, 480);
        assert_eq!(renderer.pixel_len(), 640 * 480 * 4);
    }

    #[test]
    fn test_submit_commands() {
        let renderer = GpuRenderer::new(640, 480);
        renderer.submit_command(RenderCommand::Clear {
            color: [255, 0, 0, 255],
        });
        renderer.submit_command(RenderCommand::FillRect {
            x: 10,
            y: 10,
            w: 100,
            h: 100,
            color: [0, 255, 0, 255],
        });
        renderer.present();
    }

    #[test]
    fn test_back_buffer_mutation() {
        let renderer = GpuRenderer::new(64, 64);
        renderer.with_back_buffer(|buf| {
            buf.clear([0, 0, 0, 255]);
            buf.fill_rect(0, 0, 32, 32, [255, 255, 255, 255]);
        });
    }
}
