// dala_onnx - Cross-platform ONNX Runtime wrapper for Dala
// Placeholder implementation

#![allow(unused)]

use std::ptr;
use std::sync::{Once};

static mut SESSIONS: Option<Vec<*mut ()>> = None;
static INIT: Once = Once::new();
static mut NEXT_ID: u64 = 1;

fn get_sessions() -> &'static mut Vec<*mut ()> {
    unsafe {
        INIT.call_once(|| {
            SESSIONS = Some(Vec::new());
        });
        SESSIONS.as_mut().unwrap()
    }
}

#[no_mangle]
pub extern "C" fn ort_create_session(_model_data: *const u8, _model_len: usize) -> u64 {
    let sessions = get_sessions();
    let session_id = unsafe {
        NEXT_ID += 1;
        NEXT_ID
    };
    sessions.push(ptr::null_mut());
    session_id
}

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

#[no_mangle]
pub extern "C" fn ort_run(
    _session_id: u64,
    input_data: *const f32,
    input_len: usize,
    output_data: *mut f32,
    output_len: usize,
) -> i32 {
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

#[no_mangle]
pub extern "C" fn ort_input_shape(
    _session_id: u64,
    shape_out: *mut i64,
    max_dims: usize,
) -> i32 {
    if shape_out.is_null() || max_dims < 4 {
        return -2;
    }
    unsafe {
        let shape = [1i64, 3, 224, 224];
        ptr::copy_nonoverlapping(shape.as_ptr(), shape_out, 4);
    }
    4
}

#[no_mangle]
pub extern "C" fn ort_output_shape(
    _session_id: u64,
    shape_out: *mut i64,
    max_dims: usize,
) -> i32 {
    if shape_out.is_null() || max_dims < 2 {
        return -2;
    }
    unsafe {
        let shape = [1i64, 1000];
        ptr::copy_nonoverlapping(shape.as_ptr(), shape_out, 2);
    }
    2
}

#[no_mangle]
pub extern "C" fn ort_set_execution_provider(
    _session_id: u64,
    _provider: *const char,
) -> i32 {
    0
}

#[no_mangle]
pub extern "C" fn ort_last_error() -> *const char {
    static MSG: &str = "ONNX Runtime not implemented (placeholder)";
    MSG.as_ptr() as *const char
}

#[no_mangle]
pub extern "C" fn ort_cleanup() {
    let sessions = get_sessions();
    sessions.clear();
}
