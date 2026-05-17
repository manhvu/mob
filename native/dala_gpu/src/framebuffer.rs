//! CPU-side RGBA8888 framebuffer.
//!
//! Provides pixel-level manipulation for the render thread and NIF layer.

/// A CPU-side RGBA8888 framebuffer.
///
/// Pixels are stored as a contiguous `Vec<u8>` in RGBA format (4 bytes per pixel),
/// row-major order.
pub struct FrameBuffer {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

impl FrameBuffer {
    /// Create a new framebuffer filled with black (transparent).
    pub fn new(width: u32, height: u32) -> Self {
        let size = (width * height * 4) as usize;
        Self {
            width,
            height,
            pixels: vec![0u8; size],
        }
    }

    /// Framebuffer width in pixels.
    pub fn width(&self) -> u32 {
        self.width
    }

    /// Framebuffer height in pixels.
    pub fn height(&self) -> u32 {
        self.height
    }

    /// Clear the entire framebuffer to a solid color.
    pub fn clear(&mut self, color: [u8; 4]) {
        for chunk in self.pixels.chunks_exact_mut(4) {
            chunk.copy_from_slice(&color);
        }
    }

    /// Fill a rectangle with a solid color.
    ///
    /// Clips the rectangle to the framebuffer bounds.
    pub fn fill_rect(&mut self, x: u32, y: u32, w: u32, h: u32, color: [u8; 4]) {
        let x_end = (x + w).min(self.width);
        let y_end = (y + h).min(self.height);
        let x_start = x.min(self.width);
        let y_start = y.min(self.height);

        for row in y_start..y_end {
            let row_offset = (row * self.width * 4) as usize;
            for col in x_start..x_end {
                let idx = row_offset + (col * 4) as usize;
                self.pixels[idx..idx + 4].copy_from_slice(&color);
            }
        }
    }

    /// Draw a line using Bresenham's line algorithm.
    pub fn draw_line(&mut self, x1: i32, y1: i32, x2: i32, y2: i32, color: [u8; 4]) {
        let mut x1 = x1;
        let mut y1 = y1;
        let dx = (x2 - x1).abs();
        let dy = -(y2 - y1).abs();
        let sx = if x1 < x2 { 1 } else { -1 };
        let sy = if y1 < y2 { 1 } else { -1 };
        let mut err = dx + dy;

        loop {
            self.set_pixel(x1, y1, &color);
            if x1 == x2 && y1 == y2 {
                break;
            }
            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x1 += sx;
            }
            if e2 <= dx {
                err += dx;
                y1 += sy;
            }
        }
    }

    /// Blit RGBA pixel data into the framebuffer at the given position.
    ///
    /// `data` must be `src_w * src_h * 4` bytes long.
    pub fn blit_rgba(&mut self, data: &[u8], src_w: u32, src_h: u32, dst_x: u32, dst_y: u32) {
        let copy_w = src_w.min(self.width.saturating_sub(dst_x));
        let copy_h = src_h.min(self.height.saturating_sub(dst_y));

        for row in 0..copy_h {
            let src_offset = (row * src_w * 4) as usize;
            let dst_offset = ((dst_y + row) * self.width * 4 + dst_x * 4) as usize;
            let row_bytes = (copy_w * 4) as usize;
            self.pixels[dst_offset..dst_offset + row_bytes]
                .copy_from_slice(&data[src_offset..src_offset + row_bytes]);
        }
    }

    /// Set a single pixel, clipping to bounds.
    pub fn set_pixel(&mut self, x: i32, y: i32, color: &[u8; 4]) {
        if x < 0 || y < 0 {
            return;
        }
        let x = x as u32;
        let y = y as u32;
        if x >= self.width || y >= self.height {
            return;
        }
        let idx = ((y * self.width + x) * 4) as usize;
        self.pixels[idx..idx + 4].copy_from_slice(color);
    }

    /// Get a raw pointer to the pixel data.
    pub fn pixel_ptr(&self) -> *const u8 {
        self.pixels.as_ptr()
    }

    /// Get the byte length of the pixel data.
    pub fn pixel_len(&self) -> usize {
        self.pixels.len()
    }

    /// Copy the pixel data into a new Vec.
    pub fn pixel_data(&self) -> Vec<u8> {
        self.pixels.clone()
    }

    /// Get a slice of the pixel data.
    pub fn pixels(&self) -> &[u8] {
        &self.pixels
    }

    /// Get a mutable slice of the pixel data.
    pub fn pixels_mut(&mut self) -> &mut [u8] {
        &mut self.pixels
    }

    /// Draw a circle outline using the midpoint circle algorithm.
    pub fn draw_circle(&mut self, cx: i32, cy: i32, radius: u32, color: [u8; 4]) {
        let r = radius as i32;
        let mut x = r;
        let mut y = 0;
        let mut err = 0;

        while x >= y {
            self.set_pixel(cx + x, cy + y, &color);
            self.set_pixel(cx + y, cy + x, &color);
            self.set_pixel(cx - y, cy + x, &color);
            self.set_pixel(cx - x, cy + y, &color);
            self.set_pixel(cx - x, cy - y, &color);
            self.set_pixel(cx - y, cy - x, &color);
            self.set_pixel(cx + y, cy - x, &color);
            self.set_pixel(cx + x, cy - y, &color);
            y += 1;
            err += 1 + 2 * y;
            if 2 * (err - x) + 1 > 0 {
                x -= 1;
                err += 1 - 2 * x;
            }
        }
    }

    /// Fill a circle.
    pub fn fill_circle(&mut self, cx: i32, cy: i32, radius: u32, color: [u8; 4]) {
        let r = radius as i32;
        for dy in -r..=r {
            for dx in -r..=r {
                if dx * dx + dy * dy <= r * r {
                    self.set_pixel(cx + dx, cy + dy, &color);
                }
            }
        }
    }

    /// Draw a triangle outline from three points.
    pub fn draw_triangle(
        &mut self,
        x1: i32,
        y1: i32,
        x2: i32,
        y2: i32,
        x3: i32,
        y3: i32,
        color: [u8; 4],
    ) {
        self.draw_line(x1, y1, x2, y2, color);
        self.draw_line(x2, y2, x3, y3, color);
        self.draw_line(x3, y3, x1, y1, color);
    }

    /// Fill a triangle using scanline rasterization.
    pub fn fill_triangle(
        &mut self,
        x1: i32,
        y1: i32,
        x2: i32,
        y2: i32,
        x3: i32,
        y3: i32,
        color: [u8; 4],
    ) {
        // Sort vertices by y-coordinate (bubble sort for 3 elements)
        let mut pts = [(x1, y1), (x2, y2), (x3, y3)];
        if pts[0].1 > pts[1].1 {
            pts.swap(0, 1);
        }
        if pts[1].1 > pts[2].1 {
            pts.swap(1, 2);
        }
        if pts[0].1 > pts[1].1 {
            pts.swap(0, 1);
        }
        let (x0, y0) = pts[0];
        let (x1s, y1s) = pts[1];
        let (x2, y2) = pts[2];

        // Scanline fill
        for y in y0..=y2 {
            let t = if y2 != y0 {
                (y - y0) as f32 / (y2 - y0) as f32
            } else {
                0.0
            };
            let xa = x0 as f32 + (x2 as f32 - x0 as f32) * t;
            let xb = if y < y1s && y1s != y0 {
                let t2 = (y - y0) as f32 / (y1s - y0) as f32;
                x0 as f32 + (x1s as f32 - x0 as f32) * t2
            } else {
                let t2 = if y2 != y1s {
                    (y - y1s) as f32 / (y2 - y1s) as f32
                } else {
                    0.0
                };
                x1s as f32 + (x2 as f32 - x1s as f32) * t2
            };
            let (start_x, end_x) = if xa < xb {
                (xa as i32, xb as i32)
            } else {
                (xb as i32, xa as i32)
            };
            for x in start_x..=end_x {
                self.set_pixel(x, y, &color);
            }
        }
    }

    /// Draw a rounded rectangle outline.
    pub fn draw_round_rect(&mut self, x: u32, y: u32, w: u32, h: u32, radius: u32, color: [u8; 4]) {
        let r = radius as i32;
        let x = x as i32;
        let y = y as i32;
        let w = w as i32;
        let h = h as i32;

        // Straight edges
        self.draw_line(x + r, y, x + w - r - 1, y, color);
        self.draw_line(x + r, y + h - 1, x + w - r - 1, y + h - 1, color);
        self.draw_line(x, y + r, x, y + h - r - 1, color);
        self.draw_line(x + w - 1, y + r, x + w - 1, y + h - r - 1, color);

        // Four corners
        self.draw_corner_arc(x + r, y + r, r, 180, 270, color);
        self.draw_corner_arc(x + w - r - 1, y + r, r, 270, 360, color);
        self.draw_corner_arc(x + w - r - 1, y + h - r - 1, r, 0, 90, color);
        self.draw_corner_arc(x + r, y + h - r - 1, r, 90, 180, color);
    }

    /// Fill a rounded rectangle.
    pub fn fill_round_rect(&mut self, x: u32, y: u32, w: u32, h: u32, radius: u32, color: [u8; 4]) {
        let r = radius.min(w / 2).min(h / 2);
        let x = x as i32;
        let y = y as i32;
        let w = w as i32;
        let h = h as i32;
        let r = r as i32;

        // Center rectangle
        self.fill_rect(
            (x + r) as u32,
            y as u32,
            (w - 2 * r) as u32,
            h as u32,
            color,
        );
        // Left and right strips
        self.fill_rect(
            x as u32,
            (y + r) as u32,
            r as u32,
            (h - 2 * r) as u32,
            color,
        );
        self.fill_rect(
            (x + w - r) as u32,
            (y + r) as u32,
            r as u32,
            (h - 2 * r) as u32,
            color,
        );
        // Four corner circles
        self.fill_circle(x + r, y + r, r as u32, color);
        self.fill_circle(x + w - r - 1, y + r, r as u32, color);
        self.fill_circle(x + w - r - 1, y + h - r - 1, r as u32, color);
        self.fill_circle(x + r, y + h - r - 1, r as u32, color);
    }

    // Helper: draw a quarter arc
    fn draw_corner_arc(
        &mut self,
        cx: i32,
        cy: i32,
        r: i32,
        start_deg: i32,
        end_deg: i32,
        color: [u8; 4],
    ) {
        for deg in start_deg..end_deg {
            let rad = std::f64::consts::PI * deg as f64 / 180.0;
            let px = cx + (r as f64 * rad.cos()).round() as i32;
            let py = cy + (r as f64 * rad.sin()).round() as i32;
            self.set_pixel(px, py, &color);
        }
    }

    /// Resize the framebuffer, preserving existing content where possible.
    pub fn resize(&mut self, width: u32, height: u32) {
        if self.width == width && self.height == height {
            return;
        }
        let mut new = Self::new(width, height);
        let copy_w = self.width.min(width);
        let copy_h = self.height.min(height);
        for row in 0..copy_h {
            let src_offset = (row * self.width * 4) as usize;
            let dst_offset = (row * width * 4) as usize;
            let row_bytes = (copy_w * 4) as usize;
            new.pixels[dst_offset..dst_offset + row_bytes]
                .copy_from_slice(&self.pixels[src_offset..src_offset + row_bytes]);
        }
        *self = new;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_filled_black() {
        let fb = FrameBuffer::new(4, 4);
        assert_eq!(fb.pixels(), vec![0u8; 4 * 4 * 4].as_slice());
    }

    #[test]
    fn test_clear() {
        let mut fb = FrameBuffer::new(4, 4);
        fb.clear([255, 0, 0, 255]);
        for chunk in fb.pixels().chunks_exact(4) {
            assert_eq!(chunk, &[255, 0, 0, 255]);
        }
    }

    #[test]
    fn test_fill_rect() {
        let mut fb = FrameBuffer::new(8, 8);
        fb.clear([0, 0, 0, 255]);
        fb.fill_rect(2, 2, 4, 4, [255, 0, 0, 255]);

        // Check a pixel inside the rect.
        let idx = ((2 * 8 + 2) * 4) as usize;
        assert_eq!(&fb.pixels()[idx..idx + 4], &[255, 0, 0, 255]);

        // Check a pixel outside the rect.
        let idx = (0 * 8 * 4) as usize;
        assert_eq!(&fb.pixels()[idx..idx + 4], &[0, 0, 0, 255]);
    }

    #[test]
    fn test_fill_rect_clipping() {
        let mut fb = FrameBuffer::new(4, 4);
        fb.clear([0, 0, 0, 255]);
        fb.fill_rect(2, 2, 10, 10, [255, 0, 0, 255]);

        // Only pixels (2,2), (3,2), (2,3), (3,3) should be red.
        let idx = ((2 * 4 + 2) * 4) as usize;
        assert_eq!(&fb.pixels()[idx..idx + 4], &[255, 0, 0, 255]);
    }

    #[test]
    fn test_draw_line() {
        let mut fb = FrameBuffer::new(8, 8);
        fb.clear([0, 0, 0, 255]);
        fb.draw_line(0, 0, 7, 7, [255, 255, 255, 255]);

        // Diagonal pixels should be white.
        for i in 0..8 {
            let idx = ((i * 8 + i) * 4) as usize;
            assert_eq!(&fb.pixels()[idx..idx + 4], &[255, 255, 255, 255]);
        }
    }

    #[test]
    fn test_blit_rgba() {
        let mut fb = FrameBuffer::new(8, 8);
        fb.clear([0, 0, 0, 255]);

        // 2x2 sprite of red pixels.
        let sprite = vec![
            255u8, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255,
        ];
        fb.blit_rgba(&sprite, 2, 2, 3, 3);

        // Check pixel at (3, 3).
        let idx = ((3 * 8 + 3) * 4) as usize;
        assert_eq!(&fb.pixels()[idx..idx + 4], &[255, 0, 0, 255]);

        // Check pixel at (4, 4).
        let idx = ((4 * 8 + 4) * 4) as usize;
        assert_eq!(&fb.pixels()[idx..idx + 4], &[255, 0, 0, 255]);
    }

    #[test]
    fn test_resize() {
        let mut fb = FrameBuffer::new(4, 4);
        fb.clear([255, 0, 0, 255]);
        fb.resize(8, 8);

        assert_eq!(fb.width(), 8);
        assert_eq!(fb.height(), 8);

        // Original top-left pixel should be preserved.
        assert_eq!(&fb.pixels()[0..4], &[255, 0, 0, 255]);

        // New bottom-right pixel should be black (zero-filled).
        let idx = ((7 * 8 + 7) * 4) as usize;
        assert_eq!(&fb.pixels()[idx..idx + 4], &[0, 0, 0, 0]);
    }
}
