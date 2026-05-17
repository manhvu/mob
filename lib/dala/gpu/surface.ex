defmodule Dala.Gpu.Surface do
  @moduledoc """
  GenServer that holds the state for a GPU surface.

  Each surface corresponds to a Rust-side GPU renderer with a CPU-side
  framebuffer, a command queue, and a GPU texture. The GenServer owns the
  NIF reference and ensures clean teardown via `terminate/2`.

  Commands are fire-and-forget (cast) for performance. Pixel access is
  synchronous (call) since it returns data.
  """

  use GenServer

  require Logger

  @type t :: %__MODULE__{
          ref: reference(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  defstruct [:ref, :width, :height]

  # ── Client API ────────────────────────────────────────────────────────────

  @doc "Start a linked surface GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stop the surface GenServer and free GPU resources."
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @doc "Clear the surface with a solid color."
  @spec clear(pid(), Dala.Gpu.Command.color()) :: :ok
  def clear(pid, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_clear(color)})
  end

  @doc "Fill a rectangle with a solid color."
  @spec fill_rect(
          pid(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Dala.Gpu.Command.color()
        ) :: :ok
  def fill_rect(pid, x, y, w, h, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_fill_rect(x, y, w, h, color)})
  end

  @doc "Draw a line between two points."
  @spec draw_line(pid(), integer(), integer(), integer(), integer(), Dala.Gpu.Command.color()) ::
          :ok
  def draw_line(pid, x1, y1, x2, y2, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_draw_line(x1, y1, x2, y2, color)})
  end

  @doc "Blit a loaded sprite at the given position."
  @spec blit(pid(), non_neg_integer(), integer(), integer()) :: :ok
  def blit(pid, sprite_id, x, y) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_blit(sprite_id, x, y)})
  end

  @doc "Present the surface — flush the command queue and update the GPU texture."
  @spec present(pid()) :: :ok
  def present(pid) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_present()})
  end

  @doc "Read the current pixel data as an RGBA8888 binary."
  @spec get_pixels(pid()) :: binary()
  def get_pixels(pid) do
    GenServer.call(pid, :get_pixels)
  end

  @doc "Modify pixels via a callback. The callback receives the current RGBA8888 binary
  and must return the new RGBA8888 binary of the same size."
  @spec with_pixels(pid(), (binary() -> binary())) :: :ok
  def with_pixels(pid, fun) when is_function(fun, 1) do
    GenServer.call(pid, {:with_pixels, fun})
  end

  @doc "Set the pixel data directly. Binary must be exactly width * height * 4 bytes."
  @spec set_pixels(pid(), binary()) :: :ok
  def set_pixels(pid, rgba_binary) do
    GenServer.call(pid, {:set_pixels, rgba_binary})
  end

  @doc "Load a sprite into the texture atlas for later blitting."
  @spec load_sprite(pid(), non_neg_integer(), binary(), non_neg_integer(), non_neg_integer()) ::
          :ok
  def load_sprite(pid, id, rgba_binary, width, height) do
    GenServer.cast(
      pid,
      {:command, Dala.Gpu.Command.encode_load_sprite(id, rgba_binary, width, height)}
    )
  end

  @doc "Remove a sprite from the texture atlas."
  @spec remove_sprite(pid(), non_neg_integer()) :: :ok
  def remove_sprite(pid, id) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_remove_sprite(id)})
  end

  @doc "Load an image into the GPU texture pool."
  @spec load_image(pid(), non_neg_integer(), binary(), non_neg_integer(), non_neg_integer()) :: :ok
  def load_image(pid, id, rgba_binary, width, height) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_load_image(id, rgba_binary, width, height)})
  end

  @doc "Remove an image from the GPU texture pool."
  @spec remove_image(pid(), non_neg_integer()) :: :ok
  def remove_image(pid, id) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_remove_image(id)})
  end

  @doc "Draw a loaded image onto the framebuffer."
  @spec draw_image(pid(), non_neg_integer(), integer(), integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def draw_image(pid, image_id, x, y, w, h) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_image_blit(image_id, x, y, w, h)})
  end

  @doc "Resize the surface."
  @spec resize(pid(), non_neg_integer(), non_neg_integer()) :: :ok
  def resize(pid, width, height) do
    GenServer.cast(pid, {:resize, width, height})
  end

  @doc "Get surface info as a map."
  @spec get_info(pid()) :: %{width: non_neg_integer(), height: non_neg_integer()}
  def get_info(pid) do
    GenServer.call(pid, :get_info)
  end

  @doc "Dispatch a GPU compute shader."
  @spec dispatch_compute(pid(), String.t(), binary(), {non_neg_integer(), non_neg_integer(), non_neg_integer()}) :: :ok | {:error, term()}
  def dispatch_compute(pid, shader_source, params, workgroup_count) do
    GenServer.call(pid, {:dispatch_compute, shader_source, params, workgroup_count})
  end

  @doc "Load or hot-reload a shader."
  @spec load_shader(pid(), String.t(), String.t()) :: :ok | {:error, term()}
  def load_shader(pid, name, source) do
    GenServer.cast(pid, {:load_shader, name, source})
  end

  @doc "Set a uniform value."
  @spec set_uniform(pid(), String.t(), binary()) :: :ok | {:error, term()}
  def set_uniform(pid, name, data) do
    GenServer.cast(pid, {:set_uniform, name, data})
  end

  @doc "Check compute support."
  @spec supports_compute(pid()) :: boolean()
  def supports_compute(pid) do
    GenServer.call(pid, :supports_compute)
  end

  @doc "Draw a circle outline."
  @spec draw_circle(pid(), integer(), integer(), non_neg_integer(), Dala.Gpu.Command.color()) :: :ok
  def draw_circle(pid, cx, cy, radius, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_draw_circle(cx, cy, radius, color)})
  end

  @doc "Fill a circle."
  @spec fill_circle(pid(), integer(), integer(), non_neg_integer(), Dala.Gpu.Command.color()) :: :ok
  def fill_circle(pid, cx, cy, radius, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_fill_circle(cx, cy, radius, color)})
  end

  @doc "Draw a triangle outline."
  @spec draw_triangle(pid(), integer(), integer(), integer(), integer(), integer(), integer(), Dala.Gpu.Command.color()) :: :ok
  def draw_triangle(pid, x1, y1, x2, y2, x3, y3, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_draw_triangle(x1, y1, x2, y2, x3, y3, color)})
  end

  @doc "Fill a triangle."
  @spec fill_triangle(pid(), integer(), integer(), integer(), integer(), integer(), integer(), Dala.Gpu.Command.color()) :: :ok
  def fill_triangle(pid, x1, y1, x2, y2, x3, y3, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_fill_triangle(x1, y1, x2, y2, x3, y3, color)})
  end

  @doc "Draw a rounded rectangle outline."
  @spec draw_round_rect(pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), Dala.Gpu.Command.color()) :: :ok
  def draw_round_rect(pid, x, y, w, h, radius, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_draw_round_rect(x, y, w, h, radius, color)})
  end

  @doc "Fill a rounded rectangle."
  @spec fill_round_rect(pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), Dala.Gpu.Command.color()) :: :ok
  def fill_round_rect(pid, x, y, w, h, radius, color) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_fill_round_rect(x, y, w, h, radius, color)})
  end

  @doc "Set the clipping rectangle."
  @spec set_clip(pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()) :: :ok
  def set_clip(pid, x, y, w, h, enabled) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_set_clip(x, y, w, h, enabled)})
  end

  @doc "Reset the clipping region."
  @spec reset_clip(pid()) :: :ok
  def reset_clip(pid) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_reset_clip()})
  end

  @doc "Execute a batch of pre-encoded commands."
  @spec batch(pid(), [binary()]) :: :ok
  def batch(pid, commands) do
    GenServer.cast(pid, {:command, Dala.Gpu.Command.encode_batch(commands)})
  end

  # ── Server callbacks ──────────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    ref = Dala.Gpu.Native.surface_new(width, height)

    {:ok, %__MODULE__{ref: ref, width: width, height: height}}
  end

  @impl GenServer
  def handle_cast({:command, cmd_binary}, %{ref: ref} = state) do
    Dala.Gpu.Native.surface_command(ref, cmd_binary)
    {:noreply, state}
  end

  def handle_cast({:resize, width, height}, %{ref: ref} = state) do
    Dala.Gpu.Native.surface_command(ref, Dala.Gpu.Command.encode_resize(width, height))
    {:noreply, %{state | width: width, height: height}}
  end

  def handle_cast({:load_shader, name, source}, %{ref: ref} = state) do
    cmd = Dala.Gpu.Command.encode_load_shader(name, source)
    Dala.Gpu.Native.surface_command(ref, cmd)
    {:noreply, state}
  end

  def handle_cast({:set_uniform, name, data}, %{ref: ref} = state) do
    cmd = Dala.Gpu.Command.encode_set_uniform(name, data)
    Dala.Gpu.Native.surface_command(ref, cmd)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_pixels, _from, %{ref: ref} = state) do
    pixels = Dala.Gpu.Native.surface_get_pixels(ref)
    {:reply, pixels, state}
  end

  def handle_call({:with_pixels, fun}, _from, %{ref: ref} = state) do
    pixels = Dala.Gpu.Native.surface_get_pixels(ref)
    new_pixels = fun.(pixels)
    Dala.Gpu.Native.surface_set_pixels(ref, new_pixels)
    {:reply, :ok, state}
  end

  def handle_call({:set_pixels, rgba_binary}, _from, %{ref: ref} = state) do
    Dala.Gpu.Native.surface_set_pixels(ref, rgba_binary)
    {:reply, :ok, state}
  end

  def handle_call(:get_info, _from, %{width: width, height: height} = state) do
    {:reply, %{width: width, height: height}, state}
  end

  def handle_call({:dispatch_compute, shader_source, params, workgroup_count}, _from, %{ref: ref} = state) do
    cmd = Dala.Gpu.Command.encode_dispatch_compute(shader_source, params, workgroup_count)
    result = Dala.Gpu.Native.surface_command(ref, cmd)
    {:reply, result, state}
  end

  def handle_call(:supports_compute, _from, %{ref: ref} = state) do
    result = Dala.Gpu.Native.surface_supports_compute(ref)
    {:reply, result, state}
  end

  @impl GenServer
  def terminate(_reason, %{ref: ref}) do
    Dala.Gpu.Native.surface_destroy(ref)
    :ok
  end
end
