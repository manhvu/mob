// header.rs - Public API for Dala's BEAM launcher and UI event senders
// This module declares all the C-compatible functions that are called from
// native code (Swift/Kotlin) or from dala_nif.
// Equivalent to dala_beam.h in the C implementation.

use std::os::raw::{c_char, c_int, c_void};

// ── UI Event Senders ──────────────────────────────────────────────────────

/// Send a tap event to the BEAM process registered for handle.
/// Called from Java/Kotlin when a UI element is tapped.
#[no_mangle]
pub extern "C" fn dala_send_tap(_handle: c_int) {
    // Implemented in dala_nif - this is a stub for linking
}

/// Send a {:change, tag, value} event with string value.
#[no_mangle]
pub extern "C" fn dala_send_change_str(_handle: c_int, _utf8: *const c_char) {
    // Implemented in dala_nif
}

/// Send a {:change, tag, value} event with boolean value.
#[no_mangle]
pub extern "C" fn dala_send_change_bool(_handle: c_int, _bool_val: c_int) {
    // Implemented in dala_nif
}

/// Send a {:change, tag, value} event with float value.
#[no_mangle]
pub extern "C" fn dala_send_change_float(_handle: c_int, _value: f64) {
    // Implemented in dala_nif
}

/// Send {:focus, tag} event.
#[no_mangle]
pub extern "C" fn dala_send_focus(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send {:blur, tag} event.
#[no_mangle]
pub extern "C" fn dala_send_blur(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send {:submit, tag} event.
#[no_mangle]
pub extern "C" fn dala_send_submit(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send {:select, tag} event for pickers, menus, segmented controls.
#[no_mangle]
pub extern "C" fn dala_send_select(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send {:compose, tag, %{text, phase}} for IME composition events.
#[no_mangle]
pub extern "C" fn dala_send_compose(_handle: c_int, _text: *const c_char, _phase: *const c_char) {
    // Implemented in dala_nif
}

// ── Gesture Event Senders ─────────────────────────────────────────────────

/// Send long press gesture event.
#[no_mangle]
pub extern "C" fn dala_send_long_press(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send double tap gesture event.
#[no_mangle]
pub extern "C" fn dala_send_double_tap(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send swipe left gesture event.
#[no_mangle]
pub extern "C" fn dala_send_swipe_left(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send swipe right gesture event.
#[no_mangle]
pub extern "C" fn dala_send_swipe_right(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send swipe up gesture event.
#[no_mangle]
pub extern "C" fn dala_send_swipe_up(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send swipe down gesture event.
#[no_mangle]
pub extern "C" fn dala_send_swipe_down(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send swipe with direction string.
#[no_mangle]
pub extern "C" fn dala_send_swipe_with_direction(_handle: c_int, _direction: *const c_char) {
    // Implemented in dala_nif
}

// ── High-Frequency Gesture Events (Throttled) ─────────────────────────────

/// Configure throttling for high-frequency events.
#[no_mangle]
pub extern "C" fn dala_set_throttle_config(
    _handle: c_int,
    _throttle_ms: c_int,
    _debounce_ms: c_int,
    _delta_threshold: f64,
    _leading: c_int,
    _trailing: c_int,
) {
    // Implemented in dala_nif
}

/// Send scroll event with position, delta, velocity, and phase.
#[no_mangle]
pub extern "C" fn dala_send_scroll(
    _handle: c_int,
    _x: f64,
    _y: f64,
    _dx: f64,
    _dy: f64,
    _vx: f64,
    _vy: f64,
    _phase: *const c_char,
) {
    // Implemented in dala_nif
}

/// Send drag gesture event.
#[no_mangle]
pub extern "C" fn dala_send_drag(
    _handle: c_int,
    _x: f64,
    _y: f64,
    _dx: f64,
    _dy: f64,
    _phase: *const c_char,
) {
    // Implemented in dala_nif
}

/// Send pinch gesture event.
#[no_mangle]
pub extern "C" fn dala_send_pinch(
    _handle: c_int,
    _scale: f64,
    _velocity: f64,
    _phase: *const c_char,
) {
    // Implemented in dala_nif
}

/// Send rotation gesture event.
#[no_mangle]
pub extern "C" fn dala_send_rotate(
    _handle: c_int,
    _degrees: f64,
    _velocity: f64,
    _phase: *const c_char,
) {
    // Implemented in dala_nif
}

/// Send pointer move event.
#[no_mangle]
pub extern "C" fn dala_send_pointer_move(_handle: c_int, _x: f64, _y: f64) {
    // Implemented in dala_nif
}

// ── Semantic Scroll Events ────────────────────────────────────────────────

/// Send scroll began event.
#[no_mangle]
pub extern "C" fn dala_send_scroll_began(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send scroll ended event.
#[no_mangle]
pub extern "C" fn dala_send_scroll_ended(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send scroll settled event.
#[no_mangle]
pub extern "C" fn dala_send_scroll_settled(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send top reached event.
#[no_mangle]
pub extern "C" fn dala_send_top_reached(_handle: c_int) {
    // Implemented in dala_nif
}

/// Send scrolled past threshold event.
#[no_mangle]
pub extern "C" fn dala_send_scrolled_past(_handle: c_int) {
    // Implemented in dala_nif
}

/// Handle system back gesture.
#[no_mangle]
pub extern "C" fn dala_handle_back() {
    // Implemented in dala_nif
}

// ── Device Capability Delivery ────────────────────────────────────────────

/// Deliver a 2-tuple of atoms to a PID.
#[no_mangle]
pub extern "C" fn dala_deliver_atom2(_pid: i64, _a1: *const c_char, _a2: *const c_char) {
    // Implemented in dala_nif
}

/// Deliver a 3-tuple of atoms to a PID.
#[no_mangle]
pub extern "C" fn dala_deliver_atom3(
    _pid: i64,
    _a1: *const c_char,
    _a2: *const c_char,
    _a3: *const c_char,
) {
    // Implemented in dala_nif
}

/// Deliver location update to a PID.
#[no_mangle]
pub extern "C" fn dala_deliver_location(_pid: i64, _lat: f64, _lon: f64, _acc: f64, _alt: f64) {
    // Implemented in dala_nif
}

/// Deliver motion sensor data to a PID.
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
    // Implemented in dala_nif
}

/// Deliver file picker result to a PID.
#[no_mangle]
pub extern "C" fn dala_deliver_file_result(
    _pid: i64,
    _event: *const c_char,
    _sub: *const c_char,
    _json_items: *const c_char,
) {
    // Implemented in dala_nif
}

/// Deliver push notification token to a PID.
#[no_mangle]
pub extern "C" fn dala_deliver_push_token(_pid: i64, _token: *const c_char) {
    // Implemented in dala_nif
}

/// Deliver notification payload to a PID.
#[no_mangle]
pub extern "C" fn dala_deliver_notification(_pid: i64, _json: *const c_char) {
    // Implemented in dala_nif
}

/// Set launch notification (notification that launched the app).
#[no_mangle]
pub extern "C" fn dala_set_launch_notification(_json: *const c_char) {
    // Implemented in dala_nif
}

/// Deliver alert action to the :dala_screen process.
#[no_mangle]
pub extern "C" fn dala_deliver_alert_action(_action: *const c_char) {
    // Implemented in dala_nif
}

/// Deliver component event to a native view process.
#[no_mangle]
pub extern "C" fn dala_send_component_event(
    _handle: c_int,
    _event: *const c_char,
    _payload_json: *const c_char,
) {
    // Implemented in dala_nif
}

/// Deliver color scheme change event.
#[no_mangle]
pub extern "C" fn dala_send_color_scheme_changed(_scheme: *const c_char) {
    // Implemented in dala_nif
}

// ── UI Class Caching ──────────────────────────────────────────────────────

/// Cache the bridge class for callbacks.
/// Called from JNI_OnLoad or from Java.
#[no_mangle]
pub extern "C" fn dala_ui_cache_class(_env: *mut c_void, _bridge_class: *const c_char) {
    // Implemented in dala_nif
}

// ── Global State Accessors ────────────────────────────────────────────────

/// Get the global JavaVM pointer.
/// Used by dala_nif to make callbacks to Java.
#[no_mangle]
pub static mut g_jvm: *mut c_void = std::ptr::null_mut();

/// Get the global Activity pointer.
/// Used by dala_nif for context-dependent operations.
#[no_mangle]
pub static mut g_activity: *mut c_void = std::ptr::null_mut();
