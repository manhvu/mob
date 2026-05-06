// onnx.rs - ONNX Runtime wrapper for Dala
// Provides cross-platform ONNX inference via dala_onnx crate.

use std::ffi::{c_char, c_void};
use std::ptr;
use std::sync::Once;

// ===========================================================================
// ONNX Runtime types (minimal bindings)
// ===========================================================================

type OrtSession = c_void;

// ===========================================================================
// Session management
// ===========================================================================

static mut SESSIONS: Option<Vec<*mut OrtSession>> = None;
static INIT: Once = Once::new();
static mut NEXT_ID: u64 = 1;

fn get_sessions() -> &'static mut Vec<*mut OrtSession> {
    unsafe {
        INIT.call_once(|| {
            SESSIONS = Some(Vec::new());
        });
        SESSIONS.as_mut().unwrap()
    }
}

// ===========================================================================
// C ABI functions
// ===========================================================================

/// Create an ONNX session from model data.
/// Returns: session_id (u64) on success, 0 on failure.
#[no_mangle]
pub extern "C" fn ort_create_session(model_data: *const u8, model_len: usize) -> u64 {
    // PLACEHOLDER: Real implementation would create ONNX session.
    let sessions = get_sessions();
    let session_id = unsafe {
        NEXT_ID += 1;
        NEXT_ID
    };
    sessions.push(ptr::null_mut());
    session_id
}

/// Destroy an ONNX session.
#[no_mangle]
pub extern "C" fn ort_destroy_session(session_id: u64) -> i32 {
    let sessions = get_sessions();
    let idx = (session_id - 1) as usize;
    if idx < sessions.len() {
        sessions[idx] = ptr::null_mut();
        0
    } else {
        -1
    }
}

/// Run inference on a session.
#[no_mangle]
pub extern "C" fn ort_run(
    session_id: u64,
    input_data: *const f32,
    input_len: usize,
    output_data: *mut f32,
    output_len: usize,
) -> i32 {
    // PLACEHOLDER: Real implementation would call OrtRun.
    // For now, just copy input to output (echo).
    if input_data.is_null() || output_data.is_null() {
        return -2;
    }
    unsafe {
        let input_slice = std::slice::from_raw_parts(input_data, input_len);
        let output_slice = std::slice::from_raw_parts_mut(output_data, output_len);
        let copy_len = input_len.min(output_len);
        output_slice[..copy_len].copy_from_slice(&input_slice[..copy_len]);
    }
    0
}

/// Get input tensor shape for a session.
#[no_mangle]
pub extern "C" fn ort_input_shape(session_id: u64, shape_out: *mut i64, max_dims: usize) -> i32 {
    // PLACEHOLDER: Return dummy shape [1, 3, 224, 224].
    if shape_out.is_null() || max_dims < 4 {
        return -2;
    }
    unsafe {
        let shape = [1i64, 3, 224, 224];
        std::ptr::copy_nonoverlapping(shape.as_ptr(), shape_out, 4);
    }
    4
}

/// Get output tensor shape for a session.
#[no_mangle]
pub extern "C" fn ort_output_shape(session_id: u64, shape_out: *mut i64, max_dims: usize) -> i32 {
    // PLACEHOLDER: Return dummy shape [1, 1000].
    if shape_out.is_null() || max_dims < 2 {
        return -2;
    }
    unsafe {
        let shape = [1i64, 1000];
        std::ptr::copy_nonoverlapping(shape.as_ptr(), shape_out, 2);
    }
    2
}

/// Set execution provider for a session.
#[no_mangle]
pub extern "C" fn ort_set_execution_provider(session_id: u64, provider: *const c_char) -> i32 {
    // PLACEHOLDER: Real implementation would set execution provider.
    if provider.is_null() {
        return -2;
    }
    let provider_str = unsafe { CStr::from_ptr(provider).to_string_lossy().into_owned() };
    match provider_str.as_str() {
        "coreml" => 0,
        "nnapi" => 0,
        "cpu" => 0,
        _ => -3,
    }
}

/// Get last error message.
#[no_mangle]
pub extern "C" fn ort_last_error() -> *const char {
    static ERROR_MSG: &str = "ONNX Runtime not fully implemented (placeholder)";
    ERROR_MSG.as_ptr() as *const char
}

/// Cleanup all resources.
#[no_mangle]
pub extern "C" fn ort_cleanup() {
    let sessions = get_sessions();
    sessions.clear();
}
