// header.rs - Public API for dala's BEAM launcher and UI initialization
// Equivalent to dala_beam.h in Rust
// This module declares the public Rust functions that mirror the C API

use std::os::raw::{c_char, c_int, c_void};

// ── JNI functions (called from Java/Kotlin) ─────────────────────────────

// Call from JNI_OnLoad (main thread).
// bridge_class: e.g. "com/myapp/DalaBridge"
#[no_mangle]
pub extern "C" fn dala_ui_cache_class(_env: *mut c_void, _bridge_class: *const c_char) {
    // Stub - would call _dala_ui_cache_class_impl from dala_nif
}

// Send a tap event to the BEAM process registered for handle.
// Called from the app's Java_..._DalaBridge_nativeSendTap JNI stub.
#[no_mangle]
pub extern "C" fn dala_send_tap(handle: c_int) {
    // Stub - to be implemented
}

// Send a {:change, tag, value} event.
#[no_mangle]
pub extern "C" fn dala_send_change_str(handle: c_int, utf8: *const c_char) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_change_bool(handle: c_int, bool_val: c_int) {
    // Stub - 0 = false, 1 = true
}

#[no_mangle]
pub extern "C" fn dala_send_change_float(handle: c_int, value: f64) {
    // Stub
}

// Send {:focus, tag}, {:blur, tag}, {:submit, tag} events.
#[no_mangle]
pub extern "C" fn dala_send_focus(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_blur(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_submit(handle: c_int) {
    // Stub
}

// Send {:select, tag} for pickers, menus, segmented controls.
#[no_mangle]
pub extern "C" fn dala_send_select(handle: c_int) {
    // Stub
}

// Send {:compose, tag, %{text, phase}} for IME composition events.
#[no_mangle]
pub extern "C" fn dala_send_compose(handle: c_int, text: *const c_char, phase: *const c_char) {
    // Stub
}

// ── Gesture senders (Batch 4) ─────────────────────────────────────────

#[no_mangle]
pub extern "C" fn dala_send_long_press(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_double_tap(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_swipe_left(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_swipe_right(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_swipe_up(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_swipe_down(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_swipe_with_direction(handle: c_int, direction: *const c_char) {
    // Stub
}

// ── Batch 5 Tier 1: high-frequency scroll/drag/pinch/rotate/pointer ─────

#[no_mangle]
pub extern "C" fn dala_set_throttle_config(
    handle: c_int,
    throttle_ms: c_int,
    debounce_ms: c_int,
    delta_threshold: f64,
    leading: c_int,
    trailing: c_int,
) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_scroll(
    handle: c_int,
    x: f64,
    y: f64,
    dx: f64,
    dy: f64,
    vx: f64,
    vy: f64,
    phase: *const c_char,
) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_drag(
    handle: c_int,
    x: f64,
    y: f64,
    dx: f64,
    dy: f64,
    phase: *const c_char,
) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_pinch(handle: c_int, scale: f64, velocity: f64, phase: *const c_char) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_rotate(
    handle: c_int,
    degrees: f64,
    velocity: f64,
    phase: *const c_char,
) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_pointer_move(handle: c_int, x: f64, y: f64) {
    // Stub
}

// ── Batch 5 Tier 2: semantic single-fire scroll events ──

#[no_mangle]
pub extern "C" fn dala_send_scroll_began(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_scroll_ended(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_scroll_settled(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_top_reached(handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_send_scrolled_past(handle: c_int) {
    // Stub
}

// Signal a system back gesture to the BEAM screen process.
#[no_mangle]
pub extern "C" fn dala_handle_back() {
    // Stub
}

// ── Device capability delivery functions ─────────────────────────────────

#[no_mangle]
pub extern "C" fn dala_deliver_atom2(_pid: i64, _a1: *const c_char, _a2: *const c_char) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_deliver_atom3(
    _pid: i64,
    _a1: *const c_char,
    _a2: *const c_char,
    _a3: *const c_char,
) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_deliver_location(_pid: i64, _lat: f64, _lon: f64, _acc: f64, _alt: f64) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_deliver_motion(
    _pid: i64,
    _ax: f64,
    _ay: f64,
    _az: f64,
    _gx: f64,
    _gy: f64,
    _gz: f64,
    _ts: i64,
) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_deliver_file_result(
    _pid: i64,
    _event: *const c_char,
    _sub: *const c_char,
    _json_items: *const c_char,
) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_deliver_push_token(_pid: i64, _token: *const c_char) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_deliver_notification(_pid: i64, _json: *const c_char) {
    // Stub
}

#[no_mangle]
pub extern "C" fn dala_set_launch_notification(_json: *const c_char) {
    // Stub
}

// Deliver {:alert, action_atom} to the registered :dala_screen process.
#[no_mangle]
pub extern "C" fn dala_deliver_alert_action(_action: *const c_char) {
    // Stub
}

// Deliver {:component_event, event, payload_json} to a native view component process.
#[no_mangle]
pub extern "C" fn dala_send_component_event(
    _handle: c_int,
    _event: *const c_char,
    _payload_json: *const c_char,
) {
    // Stub
}

// Deliver {:dala_device, :color_scheme_changed, :light | :dark}
#[no_mangle]
pub extern "C" fn dala_send_color_scheme_changed(_scheme: *const c_char) {
    // Stub
}
