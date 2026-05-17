//! Binary command decoder for the NIF bridge.
//!
//! Decodes the binary command format produced by `Dala.Gpu.Command` into
//! `RenderCommand` values for the render thread.

use crate::RenderCommand;

/// Decode a binary command from the Elixir side into a `RenderCommand`.
///
/// Binary format (matches `Dala.Gpu.Command` encoding):
/// - 0x01: Clear (4 bytes RGBA)
/// - 0x02: FillRect (16 bytes: x,y,w,h as u32 LE + 4 bytes RGBA)
/// - 0x03: DrawLine (16 bytes: x1,y1,x2,y2 as i32 LE + 4 bytes RGBA)
/// - 0x04: Blit (12 bytes: sprite_id as u64 LE + x,y as i32 LE)
/// - 0x05: Present (0 bytes)
/// - 0x06: Resize (8 bytes: width, height as u32 LE)
/// - 0x07: LoadSprite (16 bytes: id as u64 LE + w,h as u32 LE + pixel data)
/// - 0x08: RemoveSprite (8 bytes: id as u64 LE)
pub fn decode_command(data: &[u8]) -> RenderCommand {
    if data.is_empty() {
        return RenderCommand::Present;
    }

    match data[0] {
        0x01 => {
            // Clear
            let color = if data.len() >= 5 {
                [data[1], data[2], data[3], data[4]]
            } else {
                [0, 0, 0, 255]
            };
            RenderCommand::Clear { color }
        }
        0x02 => {
            // FillRect: x,y,w,h as u32 LE + 4 bytes RGBA
            if data.len() >= 21 {
                let x = u32::from_le_bytes(data[1..5].try_into().unwrap());
                let y = u32::from_le_bytes(data[5..9].try_into().unwrap());
                let w = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let h = u32::from_le_bytes(data[13..17].try_into().unwrap());
                let color = [data[17], data[18], data[19], data[20]];
                RenderCommand::FillRect { x, y, w, h, color }
            } else {
                RenderCommand::Present
            }
        }
        0x03 => {
            // DrawLine: x1,y1,x2,y2 as i32 LE + 4 bytes RGBA
            if data.len() >= 21 {
                let x1 = i32::from_le_bytes(data[1..5].try_into().unwrap());
                let y1 = i32::from_le_bytes(data[5..9].try_into().unwrap());
                let x2 = i32::from_le_bytes(data[9..13].try_into().unwrap());
                let y2 = i32::from_le_bytes(data[13..17].try_into().unwrap());
                let color = [data[17], data[18], data[19], data[20]];
                RenderCommand::DrawLine {
                    x1,
                    y1,
                    x2,
                    y2,
                    color,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x04 => {
            // Blit: sprite_id as u64 LE + x,y as i32 LE
            if data.len() >= 17 {
                let sprite_id = u64::from_le_bytes(data[1..9].try_into().unwrap());
                let x = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let y = u32::from_le_bytes(data[13..17].try_into().unwrap());
                RenderCommand::Blit { sprite_id, x, y }
            } else {
                RenderCommand::Present
            }
        }
        0x05 => RenderCommand::Present,
        0x06 => {
            // Resize: width, height as u32 LE
            if data.len() >= 9 {
                let width = u32::from_le_bytes(data[1..5].try_into().unwrap());
                let height = u32::from_le_bytes(data[5..9].try_into().unwrap());
                RenderCommand::Resize { width, height }
            } else {
                RenderCommand::Present
            }
        }
        0x07 => {
            // LoadSprite: id as u64 LE + w,h as u32 LE + pixel data
            if data.len() >= 17 {
                let id = u64::from_le_bytes(data[1..9].try_into().unwrap());
                let w = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let h = u32::from_le_bytes(data[13..17].try_into().unwrap());
                let pixel_data = data[17..].to_vec();
                RenderCommand::LoadSprite {
                    id,
                    w,
                    h,
                    data: pixel_data,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x08 => {
            // RemoveSprite: id as u64 LE
            if data.len() >= 9 {
                let id = u64::from_le_bytes(data[1..9].try_into().unwrap());
                RenderCommand::RemoveSprite { id }
            } else {
                RenderCommand::Present
            }
        }
        0x09 => {
            // DispatchCompute: shader_source_len as u32 LE + shader_source + params_len as u32 LE + params + workgroup_count (3xu32 LE)
            if data.len() >= 5 {
                let src_len = u32::from_le_bytes(data[1..5].try_into().unwrap()) as usize;
                if data.len() >= 5 + src_len + 4 {
                    let shader_source = String::from_utf8_lossy(&data[5..5 + src_len]).to_string();
                    let params_offset = 5 + src_len;
                    let params_len = u32::from_le_bytes(
                        data[params_offset..params_offset + 4].try_into().unwrap(),
                    ) as usize;
                    let params = data[params_offset + 4..params_offset + 4 + params_len].to_vec();
                    let wg_offset = params_offset + 4 + params_len;
                    if data.len() >= wg_offset + 12 {
                        let wg_x =
                            u32::from_le_bytes(data[wg_offset..wg_offset + 4].try_into().unwrap());
                        let wg_y = u32::from_le_bytes(
                            data[wg_offset + 4..wg_offset + 8].try_into().unwrap(),
                        );
                        let wg_z = u32::from_le_bytes(
                            data[wg_offset + 8..wg_offset + 12].try_into().unwrap(),
                        );
                        RenderCommand::DispatchCompute {
                            shader_source,
                            params,
                            workgroup_count: (wg_x, wg_y, wg_z),
                        }
                    } else {
                        RenderCommand::Present
                    }
                } else {
                    RenderCommand::Present
                }
            } else {
                RenderCommand::Present
            }
        }
        0x0A => {
            // ReadPixels: x,y,w,h as u32 LE
            if data.len() >= 17 {
                let x = u32::from_le_bytes(data[1..5].try_into().unwrap());
                let y = u32::from_le_bytes(data[5..9].try_into().unwrap());
                let w = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let h = u32::from_le_bytes(data[13..17].try_into().unwrap());
                RenderCommand::ReadPixels { x, y, w, h }
            } else {
                RenderCommand::Present
            }
        }
        0x0B => {
            // LoadShader: name_len as u32 LE + name + source_len as u32 LE + source
            if data.len() >= 5 {
                let name_len = u32::from_le_bytes(data[1..5].try_into().unwrap()) as usize;
                if data.len() >= 5 + name_len + 4 {
                    let name = String::from_utf8_lossy(&data[5..5 + name_len]).to_string();
                    let src_offset = 5 + name_len;
                    let src_len =
                        u32::from_le_bytes(data[src_offset..src_offset + 4].try_into().unwrap())
                            as usize;
                    let source =
                        String::from_utf8_lossy(&data[src_offset + 4..src_offset + 4 + src_len])
                            .to_string();
                    RenderCommand::LoadShader { name, source }
                } else {
                    RenderCommand::Present
                }
            } else {
                RenderCommand::Present
            }
        }
        0x0C => {
            // SetUniform: name_len as u32 LE + name + data_len as u32 LE + data
            if data.len() >= 5 {
                let name_len = u32::from_le_bytes(data[1..5].try_into().unwrap()) as usize;
                if data.len() >= 5 + name_len + 4 {
                    let name = String::from_utf8_lossy(&data[5..5 + name_len]).to_string();
                    let data_offset = 5 + name_len;
                    let data_len =
                        u32::from_le_bytes(data[data_offset..data_offset + 4].try_into().unwrap())
                            as usize;
                    let uniform_data = data[data_offset + 4..data_offset + 4 + data_len].to_vec();
                    RenderCommand::SetUniform {
                        name,
                        data: uniform_data,
                    }
                } else {
                    RenderCommand::Present
                }
            } else {
                RenderCommand::Present
            }
        }
        0x0D => {
            // DrawCircle: cx,cy as i32 LE + radius as u32 LE + 4 bytes RGBA
            if data.len() >= 17 {
                let cx = i32::from_le_bytes(data[1..5].try_into().unwrap());
                let cy = i32::from_le_bytes(data[5..9].try_into().unwrap());
                let radius = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let color = [data[13], data[14], data[15], data[16]];
                RenderCommand::DrawCircle {
                    cx,
                    cy,
                    radius,
                    color,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x0E => {
            // FillCircle: cx,cy as i32 LE + radius as u32 LE + 4 bytes RGBA
            if data.len() >= 17 {
                let cx = i32::from_le_bytes(data[1..5].try_into().unwrap());
                let cy = i32::from_le_bytes(data[5..9].try_into().unwrap());
                let radius = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let color = [data[13], data[14], data[15], data[16]];
                RenderCommand::FillCircle {
                    cx,
                    cy,
                    radius,
                    color,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x0F => {
            // DrawTriangle: x1,y1,x2,y2,x3,y3 as i32 LE + 4 bytes RGBA
            if data.len() >= 29 {
                let x1 = i32::from_le_bytes(data[1..5].try_into().unwrap());
                let y1 = i32::from_le_bytes(data[5..9].try_into().unwrap());
                let x2 = i32::from_le_bytes(data[9..13].try_into().unwrap());
                let y2 = i32::from_le_bytes(data[13..17].try_into().unwrap());
                let x3 = i32::from_le_bytes(data[17..21].try_into().unwrap());
                let y3 = i32::from_le_bytes(data[21..25].try_into().unwrap());
                let color = [data[25], data[26], data[27], data[28]];
                RenderCommand::DrawTriangle {
                    x1,
                    y1,
                    x2,
                    y2,
                    x3,
                    y3,
                    color,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x10 => {
            // FillTriangle: x1,y1,x2,y2,x3,y3 as i32 LE + 4 bytes RGBA
            if data.len() >= 29 {
                let x1 = i32::from_le_bytes(data[1..5].try_into().unwrap());
                let y1 = i32::from_le_bytes(data[5..9].try_into().unwrap());
                let x2 = i32::from_le_bytes(data[9..13].try_into().unwrap());
                let y2 = i32::from_le_bytes(data[13..17].try_into().unwrap());
                let x3 = i32::from_le_bytes(data[17..21].try_into().unwrap());
                let y3 = i32::from_le_bytes(data[21..25].try_into().unwrap());
                let color = [data[25], data[26], data[27], data[28]];
                RenderCommand::FillTriangle {
                    x1,
                    y1,
                    x2,
                    y2,
                    x3,
                    y3,
                    color,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x11 => {
            // DrawRoundRect: x,y,w,h as u32 LE + radius as u32 LE + 4 bytes RGBA
            if data.len() >= 25 {
                let x = u32::from_le_bytes(data[1..5].try_into().unwrap());
                let y = u32::from_le_bytes(data[5..9].try_into().unwrap());
                let w = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let h = u32::from_le_bytes(data[13..17].try_into().unwrap());
                let radius = u32::from_le_bytes(data[17..21].try_into().unwrap());
                let color = [data[21], data[22], data[23], data[24]];
                RenderCommand::DrawRoundRect {
                    x,
                    y,
                    w,
                    h,
                    radius,
                    color,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x12 => {
            // FillRoundRect: x,y,w,h as u32 LE + radius as u32 LE + 4 bytes RGBA
            if data.len() >= 25 {
                let x = u32::from_le_bytes(data[1..5].try_into().unwrap());
                let y = u32::from_le_bytes(data[5..9].try_into().unwrap());
                let w = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let h = u32::from_le_bytes(data[13..17].try_into().unwrap());
                let radius = u32::from_le_bytes(data[17..21].try_into().unwrap());
                let color = [data[21], data[22], data[23], data[24]];
                RenderCommand::FillRoundRect {
                    x,
                    y,
                    w,
                    h,
                    radius,
                    color,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x13 => {
            // SetClip: x,y,w,h as u32 LE + enabled as u8
            if data.len() >= 18 {
                let x = u32::from_le_bytes(data[1..5].try_into().unwrap());
                let y = u32::from_le_bytes(data[5..9].try_into().unwrap());
                let w = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let h = u32::from_le_bytes(data[13..17].try_into().unwrap());
                let enabled = data[17] != 0;
                RenderCommand::SetClip {
                    x,
                    y,
                    w,
                    h,
                    enabled,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x14 => RenderCommand::ResetClip,
        0x16 => {
            // ImageBlit: image_id as u64 LE + x,y as i32 LE + w,h as u32 LE
            if data.len() >= 25 {
                let image_id = u64::from_le_bytes(data[1..9].try_into().unwrap());
                let x = i32::from_le_bytes(data[9..13].try_into().unwrap());
                let y = i32::from_le_bytes(data[13..17].try_into().unwrap());
                let w = u32::from_le_bytes(data[17..21].try_into().unwrap());
                let h = u32::from_le_bytes(data[21..25].try_into().unwrap());
                RenderCommand::ImageBlit {
                    image_id,
                    x,
                    y,
                    w,
                    h,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x17 => {
            // LoadImage: id as u64 LE + w,h as u32 LE + pixel data
            if data.len() >= 17 {
                let id = u64::from_le_bytes(data[1..9].try_into().unwrap());
                let w = u32::from_le_bytes(data[9..13].try_into().unwrap());
                let h = u32::from_le_bytes(data[13..17].try_into().unwrap());
                let pixel_data = data[17..].to_vec();
                RenderCommand::LoadImage {
                    id,
                    w,
                    h,
                    data: pixel_data,
                }
            } else {
                RenderCommand::Present
            }
        }
        0x18 => {
            // RemoveImage: id as u64 LE
            if data.len() >= 9 {
                let id = u64::from_le_bytes(data[1..9].try_into().unwrap());
                RenderCommand::RemoveImage { id }
            } else {
                RenderCommand::Present
            }
        }
        0x15 => {
            // Batch: count as u32 LE + concatenated command data
            if data.len() >= 5 {
                let count = u32::from_le_bytes(data[1..5].try_into().unwrap());
                let batch_data = data[5..].to_vec();
                RenderCommand::Batch {
                    count,
                    data: batch_data,
                }
            } else {
                RenderCommand::Present
            }
        }
        _ => RenderCommand::Present,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_clear() {
        let data = vec![0x01, 255, 0, 0, 255];
        match decode_command(&data) {
            RenderCommand::Clear { color } => assert_eq!(color, [255, 0, 0, 255]),
            _ => panic!("expected Clear"),
        }
    }

    #[test]
    fn test_decode_fill_rect() {
        let mut data = vec![0x02];
        data.extend_from_slice(&10u32.to_le_bytes());
        data.extend_from_slice(&20u32.to_le_bytes());
        data.extend_from_slice(&100u32.to_le_bytes());
        data.extend_from_slice(&200u32.to_le_bytes());
        data.extend_from_slice(&[0, 255, 0, 255]);

        match decode_command(&data) {
            RenderCommand::FillRect { x, y, w, h, color } => {
                assert_eq!(x, 10);
                assert_eq!(y, 20);
                assert_eq!(w, 100);
                assert_eq!(h, 200);
                assert_eq!(color, [0, 255, 0, 255]);
            }
            _ => panic!("expected FillRect"),
        }
    }

    #[test]
    fn test_decode_present() {
        let data = vec![0x05];
        match decode_command(&data) {
            RenderCommand::Present => {}
            _ => panic!("expected Present"),
        }
    }

    #[test]
    fn test_decode_empty() {
        let data: Vec<u8> = vec![];
        match decode_command(&data) {
            RenderCommand::Present => {}
            _ => panic!("expected Present for empty data"),
        }
    }
}
