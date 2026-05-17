# GPU Render Pipeline

Dala's GPU render pipeline provides a CPU-side framebuffer that is uploaded to the GPU each frame and rendered as a fullscreen quad. This guide covers the complete GPU rendering architecture, from Elixir API to Rust render thread.

## Architecture

```
Elixir (Dala.Gpu)
    ↓ 1. Encode commands to binary (Dala.Gpu.Command)
    ↓ 2. Submit via NIF (Dala.Gpu.Native.surface_command/2)
    ↓
Rust NIF (dala_gpu)
    ↓ 3. Decode binary to RenderCommand
    ↓ 4. Send to render thread via channel
    ↓
Render Thread (dedicated)
    ↓ 5. Apply commands to back framebuffer
    ↓ 6. On Present: swap buffers, upload texture, render quad
    ↓
GPU Backend (Renderer trait)
    ↓ 7. Metal (iOS) / OpenGL ES (Android) / Stub (testing)
    ↓
GPU Texture → Fullscreen Quad → Display
```

## Surface Lifecycle

```elixir
# Create a GPU surface (spawns GenServer + Rust render thread)
{:ok, surface} = Dala.Gpu.create_surface(1920, 1080)

# Issue render commands (async, queued)
Dala.Gpu.clear(surface, :transparent)
Dala.Gpu.fill_rect(surface, 10, 10, 100, 100, :red)
Dala.Gpu.present(surface)  # flush queue, swap buffers, upload to GPU

# Cleanup
Dala.Gpu.destroy_surface(surface)
```

Each surface owns a `GpuSurface` GenServer (Elixir side), a `GpuRenderer` with dedicated render thread (Rust side), double-buffered CPU framebuffers, and a GPU backend.

## Command Queue

Render commands are encoded to a compact binary protocol and submitted asynchronously. The Rust render thread processes them on a dedicated thread, never blocking the BEAM.

### Basic Primitives

```elixir
# Clear
Dala.Gpu.clear(surface, :black)
Dala.Gpu.clear(surface, {255, 0, 0, 128})  # RGBA tuple

# Rectangle
Dala.Gpu.fill_rect(surface, x, y, w, h, :red)

# Line (Bresenham's algorithm)
Dala.Gpu.draw_line(surface, x1, y1, x2, y2, :white)

# Circle outline (midpoint circle algorithm)
Dala.Gpu.draw_circle(surface, cx, cy, radius, :blue)

# Filled circle
Dala.Gpu.fill_circle(surface, cx, cy, radius, :green)

# Triangle outline
Dala.Gpu.draw_triangle(surface, x1, y1, x2, y2, x3, y3, :yellow)

# Filled triangle (scanline rasterization)
Dala.Gpu.fill_triangle(surface, x1, y1, x2, y2, x3, y3, :cyan)

# Rounded rectangle
Dala.Gpu.draw_round_rect(surface, x, y, w, h, corner_radius, :white)
Dala.Gpu.fill_round_rect(surface, x, y, w, h, corner_radius, {0, 0, 0, 128})

# Clipping
Dala.Gpu.set_clip(surface, x, y, w, h, true)
Dala.Gpu.reset_clip(surface)
```

### Image Loading and Rendering

Images can be loaded as GPU textures and rendered with scaling:

```elixir
# Load an image from RGBA8888 binary data
Dala.Gpu.load_image(surface, image_id, rgba_data, width, height)

# Draw at position with scaling
Dala.Gpu.draw_image(surface, image_id, x, y, dest_w, dest_h)

# Remove when done
Dala.Gpu.remove_image(surface, image_id)
```

### Texture Atlas (Sprite Batching)

For frequently-drawn sprites, use the texture atlas:

```elixir
Dala.Gpu.load_sprite(surface, sprite_id, rgba_data, width, height)
Dala.Gpu.blit(surface, sprite_id, x, y)
Dala.Gpu.remove_sprite(surface, sprite_id)
```

### Batch Execution

Multiple commands can be batched for atomic execution:

```elixir
commands = [
  Dala.Gpu.Command.encode_clear(:transparent),
  Dala.Gpu.Command.encode_fill_rect(0, 0, 100, 100, :red),
  Dala.Gpu.Command.encode_draw_circle(50, 50, 25, :blue),
]
Dala.Gpu.batch(surface, commands)
```

### Compute Shaders

```elixir
Dala.Gpu.dispatch_compute(surface, shader_source, params_binary, {wg_x, wg_y, wg_z})
Dala.Gpu.load_shader(surface, "blur", new_shader_source)
Dala.Gpu.set_uniform(surface, "radius", <<5.0::float-little-32>>)
Dala.Gpu.supports_compute(surface)  # true | false
```

## Binary Command Protocol

All commands use a compact binary format: 1 byte opcode + command-specific data.

| Opcode | Command | Payload |
|--------|---------|---------|
| 0x01 | Clear | 4 bytes RGBA |
| 0x02 | FillRect | x,y,w,h u32 LE + RGBA |
| 0x03 | DrawLine | x1,y1,x2,y2 i32 LE + RGBA |
| 0x04 | Blit | sprite_id u64 LE + x,y i32 LE |
| 0x05 | Present | — |
| 0x06 | Resize | width,height u32 LE |
| 0x07 | LoadSprite | id u64 + w,h u32 + pixel data |
| 0x08 | RemoveSprite | id u64 |
| 0x09 | DispatchCompute | shader_len + shader + params_len + params + workgroup |
| 0x0A | ReadPixels | x,y,w,h u32 LE |
| 0x0B | LoadShader | name_len + name + source_len + source |
| 0x0C | SetUniform | name_len + name + data_len + data |
| 0x0D | DrawCircle | cx,cy i32 + radius u32 + RGBA |
| 0x0E | FillCircle | cx,cy i32 + radius u32 + RGBA |
| 0x0F | DrawTriangle | x1,y1,x2,y2,x3,y3 i32 + RGBA |
| 0x10 | FillTriangle | x1,y1,x2,y2,x3,y3 i32 + RGBA |
| 0x11 | DrawRoundRect | x,y,w,h,radius u32 + RGBA |
| 0x12 | FillRoundRect | x,y,w,h,radius u32 + RGBA |
| 0x13 | SetClip | x,y,w,h u32 + enabled u8 |
| 0x14 | ResetClip | — |
| 0x15 | Batch | count u32 + concatenated commands |
| 0x16 | ImageBlit | image_id u64 + x,y i32 + w,h u32 |
| 0x17 | LoadImage | id u64 + w,h u32 + pixel data |
| 0x18 | RemoveImage | id u64 |

## Double Buffering

The GPU surface uses double-buffered framebuffers. The CPU writes to the back buffer while the GPU reads from the front buffer. On `Present`, buffers swap. This avoids stalls where the CPU would wait for the GPU to finish reading.

## Scene Graph Integration

The `Dala.Media.Scene` compositor uses the GPU surface to composite multiple media sources:

```elixir
{:ok, scene} = Dala.Media.Scene.new(1920, 1080)

# Add video node (full screen)
{:ok, video} = Dala.Media.Scene.add_video(scene,
  stream: video_stream,
  size: {1920, 1080},
  z_index: 0
)

# Add PiP video overlay
{:ok, pip} = Dala.Media.Scene.add_video(scene,
  stream: pip_stream,
  pip: true,
  pip_position: {1700, 20},
  pip_size: {200, 150},
  z_index: 100
)

# Add image overlay
{:ok, img} = Dala.Media.Scene.add_image(scene,
  image_id: loaded_image_id,
  position: {100, 100},
  size: {300, 200},
  z_index: 50
)

# Composite all nodes and render
Dala.Media.Scene.render(scene)
```

### Picture-in-Picture (PiP)

PiP is achieved through the scene graph's transform system. A video or image node is added with a small size and high `z_index`:

```elixir
# Auto PiP (top-right corner, 200x150)
Dala.Media.Scene.add_video(scene, stream: stream, pip: true, z_index: 100)

# Custom PiP position and size
Dala.Media.Scene.add_video(scene, stream: stream,
  pip: true,
  pip_position: {50, 50},
  pip_size: {320, 240},
  z_index: 100
)

# Update PiP transform at runtime
Dala.Media.Scene.set_pip_transform(scene, pip_node_id,
  position: {100, 80},
  size: {400, 300}
)
```

### Node Types

| Type | Description | GPU Operation |
|------|-------------|---------------|
| `:video` | Hardware-decoded video frame | Texture blit |
| `:image` | Loaded image texture | Image blit with scaling |
| `:overlay` | Static image/UI overlay | Image blit with scaling |
| `:text` | Text rendering | Rounded rect + atlas blit |
| `:effect` | GPU compute filter | Compute shader dispatch |
| `:animation` | Animated properties | Transform update per frame |

## Direct Pixel Access

For advanced use cases, the framebuffer can be accessed directly:

```elixir
pixels = Dala.Gpu.get_pixels(surface)
Dala.Gpu.set_pixels(surface, rgba_binary)

Dala.Gpu.with_pixels(surface, fn pixels ->
  # Modify and return
  modified_pixels
end)
```

## Performance

### Command Batching
Use `batch/2` to submit multiple commands atomically, reducing channel overhead.

### Texture Pooling
Load images once, render many times. Use `Dala.Media.Texture` for pool management.

### Skip Unchanged Renders
The scene graph tracks changed nodes. If nothing changed, the render is skipped.

### Memory Budget
A 1920×1080 RGBA framebuffer is ~8MB. Double-buffered = ~16MB per surface.

## Platform Backends

**iOS (Metal):** Texture upload via `MTLTexture.replace_region`, fullscreen quad via triangle strip, compute shaders via `MTLComputePipelineState`, zero-copy from CVPixelBuffer.

**Android (OpenGL ES 3.1):** Texture upload via `glTexSubImage2D`, fullscreen quad via `GL_TRIANGLE_STRIP`, compute shaders via `glDispatchCompute`, zero-copy from SurfaceTexture.

**Stub (Testing):** No-op renderer for unit tests. Framebuffer operations work on CPU.

## References

- `lib/dala/gpu.ex` — GPU surface API
- `lib/dala/gpu/command.ex` — Binary command encoder
- `lib/dala/gpu/surface.ex` — Surface GenServer
- `lib/dala/gpu/native.ex` — NIF bindings
- `lib/dala/media/scene.ex` — Scene graph compositor
- `native/dala_gpu/src/lib.rs` — Rust render thread
- `native/dala_gpu/src/command.rs` — Render command types
- `native/dala_gpu/src/framebuffer.rs` — CPU-side framebuffer
- `native/dala_gpu/src/nif/command.rs` — Binary command decoder
- `native/dala_gpu/src/renderer/` — GPU backend trait and implementations
