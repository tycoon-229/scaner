use std::{collections::HashSet, ptr, time::Instant};

use anyd::{image::GrayFrame, symbology::Symbology};
use jni::{
    objects::{JByteArray, JObject},
    sys::{jint, jstring},
    JNIEnv,
};
use serde::Serialize;
use zedbar::{config::*, DecoderConfig, Image, Scanner, SymbolType};

const FORMAT_DATABAR: i32 = 1 << 5;
const FORMAT_DATABAR_EXPANDED: i32 = 1 << 6;
const FORMAT_PDF417: i32 = 1 << 12;
const FORMAT_MICRO_PDF417: i32 = 1 << 20;

#[derive(Serialize)]
struct DecodeResult {
    source: &'static str,
    duration_ms: u128,
    codes: Vec<DetectedCode>,
    warnings: Vec<String>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct DetectedCode {
    source: &'static str,
    text: String,
    format: i32,
    format_name: &'static str,
    raw_bytes: Vec<u8>,
    image_width: i32,
    image_height: i32,
    top_left_x: i32,
    top_left_y: i32,
    top_right_x: i32,
    top_right_y: i32,
    bottom_left_x: i32,
    bottom_left_y: i32,
    bottom_right_x: i32,
    bottom_right_y: i32,
}

#[no_mangle]
pub extern "system" fn Java_com_fpt_yuyama_scanner_gs1cca_Gs1CcaCcbRustDecoder_decodeYuvNative(
    mut env: JNIEnv,
    _class: JObject,
    image_bytes: JByteArray,
    width: jint,
    height: jint,
    row_stride: jint,
    hint_left: jint,
    hint_top: jint,
    hint_right: jint,
    hint_bottom: jint,
) -> jstring {
    let json = match decode_yuv(
        &mut env,
        image_bytes,
        width,
        height,
        row_stride,
        hint_left,
        hint_top,
        hint_right,
        hint_bottom,
    ) {
        Ok(value) => value,
        Err(message) => {
            let result = DecodeResult {
                source: "rust-gs1-cca-ccb",
                duration_ms: 0,
                codes: Vec::new(),
                warnings: vec![message],
            };
            serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string())
        }
    };

    match env.new_string(json) {
        Ok(output) => output.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn decode_yuv(
    env: &mut JNIEnv,
    image_bytes: JByteArray,
    width: jint,
    height: jint,
    row_stride: jint,
    hint_left: jint,
    hint_top: jint,
    hint_right: jint,
    hint_bottom: jint,
) -> Result<String, String> {
    if width <= 0 || height <= 0 || row_stride < width {
        return Err("Invalid image width, height, or rowStride".to_string());
    }

    let started = Instant::now();
    let width = width as usize;
    let height = height as usize;
    let row_stride = row_stride as usize;
    let luminance = env
        .convert_byte_array(image_bytes)
        .map_err(|error| format!("JNI byte array read failed: {error}"))?;
    let required_len = row_stride
        .checked_mul(height.saturating_sub(1))
        .and_then(|value| value.checked_add(width))
        .ok_or_else(|| "Image dimensions overflowed".to_string())?;
    if luminance.len() < required_len {
        return Err(format!(
            "Y plane too small: {} bytes for {}x{} stride {}",
            luminance.len(),
            width,
            height,
            row_stride
        ));
    }

    let mut codes = Vec::new();
    let mut seen = HashSet::new();
    let mut warnings = Vec::new();

    let tight = compact_luminance(&luminance, width, height, row_stride);
    match scan_databar_with_zedbar(&tight, width, height) {
        Ok(found) => append_unique(&mut codes, &mut seen, found),
        Err(error) => warnings.push(error),
    }

    let stacked_hint = HintRect::from_jints(hint_left, hint_top, hint_right, hint_bottom)
        .or_else(|| hint_from_linear_codes(&codes));
    match scan_stacked_regions_with_anyd(&luminance, width, height, row_stride, stacked_hint) {
        Ok(found) => append_unique(&mut codes, &mut seen, found),
        Err(error) => warnings.push(error),
    }

    let result = DecodeResult {
        source: "rust-gs1-cca-ccb",
        duration_ms: started.elapsed().as_millis(),
        codes,
        warnings,
    };
    serde_json::to_string(&result).map_err(|error| format!("JSON encode failed: {error}"))
}

fn compact_luminance(data: &[u8], width: usize, height: usize, row_stride: usize) -> Vec<u8> {
    if row_stride == width {
        return data[..width * height].to_vec();
    }

    let mut tight = Vec::with_capacity(width * height);
    for y in 0..height {
        let offset = y * row_stride;
        tight.extend_from_slice(&data[offset..offset + width]);
    }
    tight
}

fn scan_databar_with_zedbar(
    luminance: &[u8],
    width: usize,
    height: usize,
) -> Result<Vec<DetectedCode>, String> {
    let mut image = Image::from_gray(luminance, width as u32, height as u32)
        .map_err(|error| format!("zedbar image create failed: {error}"))?;
    let config = DecoderConfig::new()
        .enable(Databar)
        .enable(DatabarExp)
        .set_checksum(Databar, false, true)
        .set_checksum(DatabarExp, false, true)
        .position_tracking(true)
        .scan_density(1, 1);
    let mut scanner = Scanner::with_config(config);
    let symbols = scanner.scan(&mut image);

    let mut codes = Vec::new();
    for symbol in symbols {
        let (format, format_name) = match symbol.symbol_type() {
            SymbolType::Databar => (FORMAT_DATABAR, "DataBar"),
            SymbolType::DatabarExp => (FORMAT_DATABAR_EXPANDED, "DataBarExpanded"),
            _ => continue,
        };
        let raw = symbol.data().to_vec();
        let text = symbol
            .data_string()
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| visible_binary_text(&raw));
        if text.is_empty() && raw.is_empty() {
            continue;
        }
        codes.push(code_with_bounds(
            "zedbar",
            text,
            format,
            format_name,
            raw,
            width,
            height,
            symbol.bounds().map(|bounds| {
                (
                    bounds.x,
                    bounds.y,
                    bounds.x.saturating_add(bounds.width as i32),
                    bounds.y.saturating_add(bounds.height as i32),
                )
            }),
        ));
    }
    Ok(codes)
}

#[derive(Clone, Copy)]
struct HintRect {
    left: usize,
    top: usize,
    right: usize,
    bottom: usize,
}

impl HintRect {
    fn from_jints(left: jint, top: jint, right: jint, bottom: jint) -> Option<Self> {
        if left < 0 || top < 0 || right <= left || bottom <= top {
            return None;
        }
        Some(Self {
            left: left as usize,
            top: top as usize,
            right: right as usize,
            bottom: bottom as usize,
        })
    }
}

#[derive(Clone, Copy)]
struct ScanRegion {
    left: usize,
    top: usize,
    width: usize,
    height: usize,
    scale: usize,
}

fn scan_stacked_regions_with_anyd(
    luminance: &[u8],
    width: usize,
    height: usize,
    row_stride: usize,
    hint: Option<HintRect>,
) -> Result<Vec<DetectedCode>, String> {
    let mut codes = Vec::new();
    let mut seen = HashSet::new();
    for region in scan_regions(width, height, hint) {
        let found = scan_stacked_region_with_anyd(luminance, width, height, row_stride, region)?;
        append_unique(&mut codes, &mut seen, found);
    }
    Ok(codes)
}

fn scan_regions(width: usize, height: usize, hint: Option<HintRect>) -> Vec<ScanRegion> {
    let mut regions = Vec::new();

    let Some(hint) = hint else {
        return regions;
    };

    let hint_left = hint.left.min(width.saturating_sub(1));
    let hint_right = hint.right.min(width).max(hint_left + 1);
    let hint_top = hint.top.min(height.saturating_sub(1));
    let hint_bottom = hint.bottom.min(height).max(hint_top + 1);
    let hint_width = hint_right - hint_left;
    let hint_height = hint_bottom - hint_top;
    let margin_x = (hint_width / 3).max(24);
    let above_height = (hint_height * 4).max(height / 5).max(80);
    let left = hint_left.saturating_sub(margin_x);
    let right = (hint_right + margin_x).min(width);
    let top = hint_top.saturating_sub(above_height);
    let bottom = (hint_top + hint_height / 3).min(height);
    if right > left && bottom > top {
        let region_width = right - left;
        let region_height = bottom - top;
        regions.push(ScanRegion {
            left,
            top,
            width: region_width,
            height: region_height,
            scale: 2,
        });
        if region_width.saturating_mul(region_height) <= 180_000 {
            regions.push(ScanRegion {
                left,
                top,
                width: region_width,
                height: region_height,
                scale: 3,
            });
        }
    }

    regions
}

fn hint_from_linear_codes(codes: &[DetectedCode]) -> Option<HintRect> {
    for code in codes.iter().rev() {
        if code.format != FORMAT_DATABAR && code.format != FORMAT_DATABAR_EXPANDED {
            continue;
        }

        let left = code.top_left_x.min(code.bottom_left_x).max(0) as usize;
        let top = code.top_left_y.min(code.top_right_y).max(0) as usize;
        let right = code.top_right_x.max(code.bottom_right_x).max(0) as usize;
        let bottom = code.bottom_left_y.max(code.bottom_right_y).max(0) as usize;
        if right > left && bottom > top {
            return Some(HintRect {
                left,
                top,
                right,
                bottom,
            });
        }
    }
    None
}

fn scan_stacked_region_with_anyd(
    luminance: &[u8],
    image_width: usize,
    image_height: usize,
    row_stride: usize,
    region: ScanRegion,
) -> Result<Vec<DetectedCode>, String> {
    let region_width = region.width.min(image_width.saturating_sub(region.left));
    let region_height = region.height.min(image_height.saturating_sub(region.top));
    if region_width == 0 || region_height == 0 {
        return Ok(Vec::new());
    }

    let (buffer, scan_width, scan_height) = copy_region_scaled(
        luminance,
        row_stride,
        region.left,
        region.top,
        region_width,
        region_height,
        region.scale,
    );
    let frame = GrayFrame::new(&buffer, scan_width, scan_height)
        .map_err(|error| format!("anyd frame create failed: {error}"))?;
    let symbols = anyd::pipeline::scan_2d(&frame);

    let mut codes = Vec::new();
    for symbol in symbols {
        let (format, format_name) = match symbol.symbology {
            Symbology::MicroPdf417 => (FORMAT_MICRO_PDF417, "MicroPDF417"),
            Symbology::Pdf417 => (FORMAT_PDF417, "PDF417"),
            _ => continue,
        };
        let raw = symbol.payload_bytes();
        let text = symbol.text().unwrap_or_else(|| visible_binary_text(&raw));
        if text.is_empty() && raw.is_empty() {
            continue;
        }
        let bounds = symbol.location.as_ref().map(|location| {
            let (min, max) = location.outline.bounds();
            (
                region.left as i32 + (min.x / region.scale as f32).floor() as i32,
                region.top as i32 + (min.y / region.scale as f32).floor() as i32,
                region.left as i32 + (max.x / region.scale as f32).ceil() as i32,
                region.top as i32 + (max.y / region.scale as f32).ceil() as i32,
            )
        });
        codes.push(code_with_bounds(
            "anyd",
            text,
            format,
            format_name,
            raw,
            image_width,
            image_height,
            bounds,
        ));
    }
    Ok(codes)
}

fn copy_region_scaled(
    data: &[u8],
    row_stride: usize,
    left: usize,
    top: usize,
    width: usize,
    height: usize,
    scale: usize,
) -> (Vec<u8>, usize, usize) {
    let scale = scale.max(1);
    if scale == 1 {
        let mut out = Vec::with_capacity(width * height);
        for y in 0..height {
            let src = (top + y) * row_stride + left;
            out.extend_from_slice(&data[src..src + width]);
        }
        return (out, width, height);
    }

    let scaled_width = width * scale;
    let scaled_height = height * scale;
    let mut out = vec![0u8; scaled_width * scaled_height];
    for y in 0..height {
        let src = (top + y) * row_stride + left;
        for sy in 0..scale {
            let dst_row = (y * scale + sy) * scaled_width;
            for x in 0..width {
                let value = data[src + x];
                let dst = dst_row + x * scale;
                for sx in 0..scale {
                    out[dst + sx] = value;
                }
            }
        }
    }
    (out, scaled_width, scaled_height)
}

fn append_unique(
    output: &mut Vec<DetectedCode>,
    seen: &mut HashSet<String>,
    candidates: Vec<DetectedCode>,
) {
    for candidate in candidates {
        let key = format!(
            "{}|{}|{}",
            candidate.source, candidate.format, candidate.text
        );
        if seen.insert(key) {
            output.push(candidate);
        }
    }
}

fn code_with_bounds(
    source: &'static str,
    text: String,
    format: i32,
    format_name: &'static str,
    raw_bytes: Vec<u8>,
    width: usize,
    height: usize,
    bounds: Option<(i32, i32, i32, i32)>,
) -> DetectedCode {
    let (left, top, right, bottom) = bounds.unwrap_or((0, 0, width as i32, height as i32));
    DetectedCode {
        source,
        text,
        format,
        format_name,
        raw_bytes,
        image_width: width as i32,
        image_height: height as i32,
        top_left_x: left,
        top_left_y: top,
        top_right_x: right,
        top_right_y: top,
        bottom_left_x: left,
        bottom_left_y: bottom,
        bottom_right_x: right,
        bottom_right_y: bottom,
    }
}

fn visible_binary_text(bytes: &[u8]) -> String {
    let mut out = String::new();
    for &byte in bytes {
        match byte {
            8 => out.push_str("<BS>"),
            10 => out.push_str("<LF>"),
            13 => out.push_str("<CR>"),
            29 => out.push_str("<GS>"),
            32..=126 => out.push(byte as char),
            _ => out.push_str(&format!("<U+{byte:02X}>")),
        }
    }
    out
}
