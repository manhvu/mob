defmodule Dala.Gpu.Command do
  @moduledoc """
  Encodes render commands to binary format for the Rust command queue.

  Binary format:
  - 1 byte: command type
  - N bytes: command-specific data

  Command types:
  - 0x01: Clear (4 bytes RGBA)
  - 0x02: FillRect (16 bytes: x,y,w,h as u32 LE + 4 bytes RGBA)
  - 0x03: DrawLine (16 bytes: x1,y1,x2,y2 as i32 LE + 4 bytes RGBA)
  - 0x04: Blit (12 bytes: sprite_id as u64 LE + x,y as u32 LE)
  - 0x05: Present (0 bytes)
  - 0x06: Resize (8 bytes: width, height as u32 LE)
  - 0x07: LoadSprite (16 bytes: id as u64 LE + w,h as u32 LE + pixel data)
  - 0x08: RemoveSprite (8 bytes: id as u64 LE)
  """

  @type color :: atom() | {0..255, 0..255, 0..255} | {0..255, 0..255, 0..255, 0..255}

  # ── Command encoding ──────────────────────────────────────────────────────

  @doc "Encode a clear command that fills the entire surface with a solid color."
  @spec encode_clear(color()) :: binary()
  def encode_clear(color) do
    rgba = color_to_rgba(color)
    <<0x01, rgba::binary>>
  end

  @doc "Encode a fill_rect command that fills a rectangle with a solid color."
  @spec encode_fill_rect(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          color()
        ) :: binary()
  def encode_fill_rect(x, y, w, h, color) do
    rgba = color_to_rgba(color)

    <<0x02, x::unsigned-little-32, y::unsigned-little-32, w::unsigned-little-32,
      h::unsigned-little-32, rgba::binary>>
  end

  @doc "Encode a draw_line command that draws a line between two points."
  @spec encode_draw_line(integer(), integer(), integer(), integer(), color()) :: binary()
  def encode_draw_line(x1, y1, x2, y2, color) do
    rgba = color_to_rgba(color)

    <<0x03, x1::signed-little-32, y1::signed-little-32, x2::signed-little-32,
      y2::signed-little-32, rgba::binary>>
  end

  @doc "Encode a blit command that draws a loaded sprite at the given position."
  @spec encode_blit(non_neg_integer(), integer(), integer()) :: binary()
  def encode_blit(sprite_id, x, y) do
    <<0x04, sprite_id::unsigned-little-64, x::signed-little-32, y::signed-little-32>>
  end

  @doc "Encode a present command that flushes the command queue and updates the GPU texture."
  @spec encode_present() :: binary()
  def encode_present do
    <<0x05>>
  end

  @doc "Encode a resize command that changes the surface dimensions."
  @spec encode_resize(non_neg_integer(), non_neg_integer()) :: binary()
  def encode_resize(width, height) do
    <<0x06, width::unsigned-little-32, height::unsigned-little-32>>
  end

  @doc "Encode a load_sprite command that uploads pixel data into the texture atlas."
  @spec encode_load_sprite(non_neg_integer(), binary(), non_neg_integer(), non_neg_integer()) ::
          binary()
  def encode_load_sprite(id, rgba_data, width, height) do
    <<0x07, id::unsigned-little-64, width::unsigned-little-32, height::unsigned-little-32,
      rgba_data::binary>>
  end

  @doc "Encode a remove_sprite command that frees a sprite from the texture atlas."
  @spec encode_remove_sprite(non_neg_integer()) :: binary()
  def encode_remove_sprite(id) do
    <<0x08, id::unsigned-little-64>>
  end

  @doc "Encode a load_image command that uploads an image as a GPU texture."
  @spec encode_load_image(non_neg_integer(), binary(), non_neg_integer(), non_neg_integer()) :: binary()
  def encode_load_image(id, rgba_data, width, height) do
    <<0x17, id::unsigned-little-64, width::unsigned-little-32, height::unsigned-little-32,
      rgba_data::binary>>
  end

  @doc "Encode a remove_image command that frees an image texture."
  @spec encode_remove_image(non_neg_integer()) :: binary()
  def encode_remove_image(id) do
    <<0x18, id::unsigned-little-64>>
  end

  @doc "Encode a dispatch_compute command that runs a GPU compute shader."
  @spec encode_dispatch_compute(String.t(), binary(), {non_neg_integer(), non_neg_integer(), non_neg_integer()}) :: binary()
  def encode_dispatch_compute(shader_source, params, {wg_x, wg_y, wg_z}) do
    src_bytes = :erlang.term_to_binary(shader_source)
    src_len = byte_size(src_bytes)
    params_len = byte_size(params)

    <<0x09, src_len::unsigned-little-32, src_bytes::binary,
      params_len::unsigned-little-32, params::binary,
      wg_x::unsigned-little-32, wg_y::unsigned-little-32, wg_z::unsigned-little-32>>
  end

  @doc "Encode a read_pixels command that reads back GPU texture data."
  @spec encode_read_pixels(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: binary()
  def encode_read_pixels(x, y, w, h) do
    <<0x0A, x::unsigned-little-32, y::unsigned-little-32, w::unsigned-little-32, h::unsigned-little-32>>
  end

  @doc "Encode a load_shader command for hot-reloading shaders."
  @spec encode_load_shader(String.t(), String.t()) :: binary()
  def encode_load_shader(name, source) do
    name_bytes = :erlang.term_to_binary(name)
    name_len = byte_size(name_bytes)
    src_bytes = :erlang.term_to_binary(source)
    src_len = byte_size(src_bytes)

    <<0x0B, name_len::unsigned-little-32, name_bytes::binary,
      src_len::unsigned-little-32, src_bytes::binary>>
  end

  @doc "Encode a set_uniform command for shader parameters."
  @spec encode_set_uniform(String.t(), binary()) :: binary()
  def encode_set_uniform(name, data) do
    name_bytes = :erlang.term_to_binary(name)
    name_len = byte_size(name_bytes)
    data_len = byte_size(data)

    <<0x0C, name_len::unsigned-little-32, name_bytes::binary,
      data_len::unsigned-little-32, data::binary>>
  end

  @doc "Encode an image_blit command that draws a loaded image texture."
  @spec encode_image_blit(non_neg_integer(), integer(), integer(), non_neg_integer(), non_neg_integer()) :: binary()
  def encode_image_blit(image_id, x, y, w, h) do
    <<0x16, image_id::unsigned-little-64, x::signed-little-32, y::signed-little-32,
      w::unsigned-little-32, h::unsigned-little-32>>
  end

  @doc "Encode a draw_circle command."
  @spec encode_draw_circle(integer(), integer(), non_neg_integer(), color()) :: binary()
  def encode_draw_circle(cx, cy, radius, color) do
    rgba = color_to_rgba(color)
    <<0x0D, cx::signed-little-32, cy::signed-little-32, radius::unsigned-little-32, rgba::binary>>
  end

  @doc "Encode a fill_circle command."
  @spec encode_fill_circle(integer(), integer(), non_neg_integer(), color()) :: binary()
  def encode_fill_circle(cx, cy, radius, color) do
    rgba = color_to_rgba(color)
    <<0x0E, cx::signed-little-32, cy::signed-little-32, radius::unsigned-little-32, rgba::binary>>
  end

  @doc "Encode a draw_triangle command."
  @spec encode_draw_triangle(integer(), integer(), integer(), integer(), integer(), integer(), color()) :: binary()
  def encode_draw_triangle(x1, y1, x2, y2, x3, y3, color) do
    rgba = color_to_rgba(color)
    <<0x0F, x1::signed-little-32, y1::signed-little-32, x2::signed-little-32,
      y2::signed-little-32, x3::signed-little-32, y3::signed-little-32, rgba::binary>>
  end

  @doc "Encode a fill_triangle command."
  @spec encode_fill_triangle(integer(), integer(), integer(), integer(), integer(), integer(), color()) :: binary()
  def encode_fill_triangle(x1, y1, x2, y2, x3, y3, color) do
    rgba = color_to_rgba(color)
    <<0x10, x1::signed-little-32, y1::signed-little-32, x2::signed-little-32,
      y2::signed-little-32, x3::signed-little-32, y3::signed-little-32, rgba::binary>>
  end

  @doc "Encode a draw_round_rect command."
  @spec encode_draw_round_rect(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), color()) :: binary()
  def encode_draw_round_rect(x, y, w, h, radius, color) do
    rgba = color_to_rgba(color)
    <<0x11, x::unsigned-little-32, y::unsigned-little-32, w::unsigned-little-32,
      h::unsigned-little-32, radius::unsigned-little-32, rgba::binary>>
  end

  @doc "Encode a fill_round_rect command."
  @spec encode_fill_round_rect(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), color()) :: binary()
  def encode_fill_round_rect(x, y, w, h, radius, color) do
    rgba = color_to_rgba(color)
    <<0x12, x::unsigned-little-32, y::unsigned-little-32, w::unsigned-little-32,
      h::unsigned-little-32, radius::unsigned-little-32, rgba::binary>>
  end

  @doc "Encode a set_clip command."
  @spec encode_set_clip(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()) :: binary()
  def encode_set_clip(x, y, w, h, enabled) do
    flag = if enabled, do: 1, else: 0
    <<0x13, x::unsigned-little-32, y::unsigned-little-32, w::unsigned-little-32,
      h::unsigned-little-32, flag::unsigned-little-8>>
  end

  @doc "Encode a reset_clip command."
  @spec encode_reset_clip() :: binary()
  def encode_reset_clip do
    <<0x14>>
  end

  @doc "Encode a batch command containing multiple sub-commands."
  @spec encode_batch([binary()]) :: binary()
  def encode_batch(commands) do
    data = :erlang.list_to_binary(commands)
    count = length(commands)
    <<0x15, count::unsigned-little-32, data::binary>>
  end

  # ── Color encoding ────────────────────────────────────────────────────────

  @doc "Convert a color to a 4-byte RGBA binary."
  @spec color_to_rgba(color()) :: binary()
  def color_to_rgba(:black), do: <<0, 0, 0, 255>>
  def color_to_rgba(:white), do: <<255, 255, 255, 255>>
  def color_to_rgba(:red), do: <<255, 0, 0, 255>>
  def color_to_rgba(:green), do: <<0, 255, 0, 255>>
  def color_to_rgba(:blue), do: <<0, 0, 255, 255>>
  def color_to_rgba(:transparent), do: <<0, 0, 0, 0>>
  def color_to_rgba({r, g, b, a}), do: <<r, g, b, a>>
  def color_to_rgba({r, g, b}), do: <<r, g, b, 255>>
end
