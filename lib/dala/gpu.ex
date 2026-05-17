defmodule Dala.Gpu do
  @moduledoc """
  GPU texture rendering surface.

  Provides a CPU-side framebuffer that is uploaded to the GPU every frame
  and rendered as a fullscreen quad. This is useful for:
  - Custom canvas rendering
  - ML tensor visualization
  - Game-like rendering
  - Video processing
  - Shader effects

  The rendering pipeline:
  1. Elixir issues render commands (fill_rect, blit, etc.)
  2. Rust processes commands on a dedicated render thread
  3. CPU framebuffer is uploaded as GPU texture
  4. Fullscreen quad is rendered with the texture

  ## Example

      # Create a 256x256 GPU surface
      {:ok, surface} = Dala.Gpu.create_surface(256, 256)

      # Issue render commands
      Dala.Gpu.clear(surface, :black)
      Dala.Gpu.fill_rect(surface, 10, 10, 100, 100, :red)
      Dala.Gpu.present(surface)

      # Direct pixel access (for advanced use)
      Dala.Gpu.with_pixels(surface, fn pixels ->
        # pixels is a binary of RGBA8888 data
        # modify directly for maximum performance
      end)
  """

  alias Dala.Gpu.Surface

  @type surface_pid :: pid()
  @type color :: Dala.Gpu.Command.color()

  # ── Surface lifecycle ─────────────────────────────────────────────────────

  @doc """
  Create a new GPU surface with the given dimensions.

  Returns `{:ok, pid}` where pid is the surface GenServer.
  The surface is automatically cleaned up when the calling process exits
  or when `destroy_surface/1` is called.
  """
  @spec create_surface(non_neg_integer(), non_neg_integer()) ::
          {:ok, surface_pid()} | {:error, term()}
  def create_surface(width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    Surface.start_link(width: width, height: height)
  end

  @doc "Destroy a GPU surface and free all associated GPU resources."
  @spec destroy_surface(surface_pid()) :: :ok
  def destroy_surface(pid) do
    Surface.stop(pid)
  end

  @doc "Resize an existing GPU surface. This may reallocate the GPU texture."
  @spec resize_surface(surface_pid(), non_neg_integer(), non_neg_integer()) :: :ok
  def resize_surface(pid, width, height) do
    Surface.resize(pid, width, height)
  end

  # ── Render commands (async, queued) ───────────────────────────────────────

  @doc "Clear the entire surface with a solid color."
  @spec clear(surface_pid(), color()) :: :ok
  def clear(pid, color) do
    Surface.clear(pid, color)
  end

  @doc "Fill a rectangle with a solid color."
  @spec fill_rect(
          surface_pid(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          color()
        ) :: :ok
  def fill_rect(pid, x, y, w, h, color) do
    Surface.fill_rect(pid, x, y, w, h, color)
  end

  @doc "Draw a line between two points with the given color."
  @spec draw_line(surface_pid(), integer(), integer(), integer(), integer(), color()) :: :ok
  def draw_line(pid, x1, y1, x2, y2, color) do
    Surface.draw_line(pid, x1, y1, x2, y2, color)
  end

  @doc "Blit a loaded sprite at the given position."
  @spec blit(surface_pid(), non_neg_integer(), integer(), integer()) :: :ok
  def blit(pid, sprite_id, x, y) do
    Surface.blit(pid, sprite_id, x, y)
  end

  @doc "Present the surface — flush the command queue and update the GPU texture."
  @spec present(surface_pid()) :: :ok
  def present(pid) do
    Surface.present(pid)
  end

  # ── Direct pixel access ───────────────────────────────────────────────────

  @doc """
  Get the current pixel data as an RGBA8888 binary.

  The binary size is `width * height * 4` bytes.
  """
  @spec get_pixels(surface_pid()) :: binary()
  def get_pixels(pid) do
    Surface.get_pixels(pid)
  end

  @doc """
  Set the pixel data directly from an RGBA8888 binary.

  The binary must be exactly `width * height * 4` bytes.
  """
  @spec set_pixels(surface_pid(), binary()) :: :ok
  def set_pixels(pid, rgba_binary) do
    Surface.set_pixels(pid, rgba_binary)
  end

  @doc """
  Modify pixels via a callback for maximum performance.

  The callback receives the current RGBA8888 binary and must return
  a new RGBA8888 binary of the same size. This avoids an extra
  binary copy compared to `get_pixels`/`set_pixels`.

  ## Example

      Dala.Gpu.with_pixels(surface, fn pixels ->
        # Set the first pixel to red
        <<255, 0, 0, 255, rest::binary>> = pixels
        rest
      end)
  """
  @spec with_pixels(surface_pid(), (binary() -> binary())) :: :ok
  def with_pixels(pid, fun) do
    Surface.with_pixels(pid, fun)
  end

  # ── Surface info ──────────────────────────────────────────────────────────

  @doc "Get the width of the surface in pixels."
  @spec width(surface_pid()) :: non_neg_integer()
  def width(pid) do
    %{width: w} = Surface.get_info(pid)
    w
  end

  @doc "Get the height of the surface in pixels."
  @spec height(surface_pid()) :: non_neg_integer()
  def height(pid) do
    %{height: h} = Surface.get_info(pid)
    h
  end

  # ── Texture atlas management ──────────────────────────────────────────────

  @doc """
  Load a sprite into the texture atlas for later blitting.

  `id` is a unique non-negative integer identifying the sprite.
  `rgba_binary` is the pixel data in RGBA8888 format.
  """
  @spec load_sprite(
          surface_pid(),
          non_neg_integer(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def load_sprite(pid, id, rgba_binary, width, height) do
    Surface.load_sprite(pid, id, rgba_binary, width, height)
  end

  @doc "Remove a sprite from the texture atlas."
  @spec remove_sprite(surface_pid(), non_neg_integer()) :: :ok
  def remove_sprite(pid, id) do
    Surface.remove_sprite(pid, id)
  end

  # ── Image loading ────────────────────────────────────────────────────────

  @doc """
  Load an image into the GPU texture pool.

  `id` is a unique non-negative integer identifying the image.
  `rgba_binary` is the pixel data in RGBA8888 format.

  The image can then be rendered with `draw_image/6`.

  ## Example

      # Load a PNG-decoded binary
      {:ok, rgba_data} = Image.load("photo.png")
      Dala.Gpu.load_image(surface, 1, rgba_data, 640, 480)

      # Draw it at position (100, 200) scaled to 320x240
      Dala.Gpu.draw_image(surface, 1, 100, 200, 320, 240)
  """
  @spec load_image(
          surface_pid(),
          non_neg_integer(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def load_image(pid, id, rgba_binary, width, height) do
    Surface.load_image(pid, id, rgba_binary, width, height)
  end

  @doc "Remove an image from the GPU texture pool."
  @spec remove_image(surface_pid(), non_neg_integer()) :: :ok
  def remove_image(pid, id) do
    Surface.remove_image(pid, id)
  end

  @doc """
  Draw a loaded image onto the framebuffer at the given position and size.

  The image is scaled to fit the destination rectangle. For best quality,
  load the image at its native resolution and scale via the destination size.

  ## Example

      # Full-size render
      Dala.Gpu.draw_image(surface, image_id, 0, 0, 640, 480)

      # PiP mode: small overlay in the corner
      Dala.Gpu.draw_image(surface, image_id, 540, 20, 120, 90)
  """
  @spec draw_image(
          surface_pid(),
          non_neg_integer(),
          integer(),
          integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def draw_image(pid, image_id, x, y, w, h) do
    Surface.draw_image(pid, image_id, x, y, w, h)
  end

  # ── GPU compute ──────────────────────────────────────────────────────────

  @doc """
  Dispatch a GPU compute shader on the surface.

  `shader_source` is the shader source code (MSL for Metal, GLSL for OpenGL ES).
  `params` is a binary of parameter data passed to the shader.
  `workgroup_count` is the number of threadgroups to dispatch {x, y, z}.

  For filter presets, see `Dala.Media.Filter`.
  """
  @spec dispatch_compute(surface_pid(), String.t(), binary(), {non_neg_integer(), non_neg_integer(), non_neg_integer()}) :: :ok | {:error, term()}
  def dispatch_compute(pid, shader_source, params \\ <<>>, workgroup_count \\ {1, 1, 1}) do
    Surface.dispatch_compute(pid, shader_source, params, workgroup_count)
  end

  @doc "Load or hot-reload a named shader."
  @spec load_shader(surface_pid(), String.t(), String.t()) :: :ok | {:error, term()}
  def load_shader(pid, name, source) do
    Surface.load_shader(pid, name, source)
  end

  @doc "Set a uniform value on the current shader pipeline."
  @spec set_uniform(surface_pid(), String.t(), binary()) :: :ok | {:error, term()}
  def set_uniform(pid, name, data) do
    Surface.set_uniform(pid, name, data)
  end

  @doc "Check if the GPU backend supports compute shaders."
  @spec supports_compute(surface_pid()) :: boolean()
  def supports_compute(pid) do
    Surface.supports_compute(pid)
  end

  # ── Complex drawing commands ──────────────────────────────────────────────

  @doc "Draw a circle outline."
  @spec draw_circle(surface_pid(), integer(), integer(), non_neg_integer(), color()) :: :ok
  def draw_circle(pid, cx, cy, radius, color) do
    Surface.draw_circle(pid, cx, cy, radius, color)
  end

  @doc "Fill a circle."
  @spec fill_circle(surface_pid(), integer(), integer(), non_neg_integer(), color()) :: :ok
  def fill_circle(pid, cx, cy, radius, color) do
    Surface.fill_circle(pid, cx, cy, radius, color)
  end

  @doc "Draw a triangle outline from three points."
  @spec draw_triangle(surface_pid(), integer(), integer(), integer(), integer(), integer(), integer(), color()) :: :ok
  def draw_triangle(pid, x1, y1, x2, y2, x3, y3, color) do
    Surface.draw_triangle(pid, x1, y1, x2, y2, x3, y3, color)
  end

  @doc "Fill a triangle."
  @spec fill_triangle(surface_pid(), integer(), integer(), integer(), integer(), integer(), integer(), color()) :: :ok
  def fill_triangle(pid, x1, y1, x2, y2, x3, y3, color) do
    Surface.fill_triangle(pid, x1, y1, x2, y2, x3, y3, color)
  end

  @doc "Draw a rounded rectangle outline."
  @spec draw_round_rect(surface_pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), color()) :: :ok
  def draw_round_rect(pid, x, y, w, h, radius, color) do
    Surface.draw_round_rect(pid, x, y, w, h, radius, color)
  end

  @doc "Fill a rounded rectangle."
  @spec fill_round_rect(surface_pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), color()) :: :ok
  def fill_round_rect(pid, x, y, w, h, radius, color) do
    Surface.fill_round_rect(pid, x, y, w, h, radius, color)
  end

  @doc "Set the clipping rectangle. Pass `enabled: false` to disable clipping."
  @spec set_clip(surface_pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()) :: :ok
  def set_clip(pid, x, y, w, h, enabled \\ true) do
    Surface.set_clip(pid, x, y, w, h, enabled)
  end

  @doc "Reset the clipping region to the full framebuffer."
  @spec reset_clip(surface_pid()) :: :ok
  def reset_clip(pid) do
    Surface.reset_clip(pid)
  end

  @doc "Execute a batch of pre-encoded command binaries atomically."
  @spec batch(surface_pid(), [binary()]) :: :ok
  def batch(pid, commands) when is_list(commands) do
    Surface.batch(pid, commands)
  end
end
