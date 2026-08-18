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
) -> jstring {
    let json = match decode_yuv(&mut env, image_bytes, width, height, row_stride) {
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

    match scan_stacked_with_anyd(&luminance, width, height, row_stride) {
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

fn scan_stacked_with_anyd(
    luminance: &[u8],
    width: usize,
    height: usize,
    row_stride: usize,
) -> Result<Vec<DetectedCode>, String> {
    let frame = GrayFrame::with_stride(luminance, width, height, row_stride)
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
                min.x.round() as i32,
                min.y.round() as i32,
                max.x.round() as i32,
                max.y.round() as i32,
            )
        });
        codes.push(code_with_bounds(
            "anyd",
            text,
            format,
            format_name,
            raw,
            width,
            height,
            bounds,
        ));
    }
    Ok(codes)
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
