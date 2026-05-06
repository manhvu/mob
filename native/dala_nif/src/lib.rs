use rustler::{Binary, Env, NifResult, Term};
use std::ffi::c_void;
use std::sync::Mutex;

#[cfg(target_os = "android")]
mod android;
mod common;
#[cfg(target_os = "ios")]
mod ios;
mod protocol;
mod tree;

use common::*;
use protocol::*;
use tree::*;

// Global tree for patch-based rendering
lazy_static::lazy_static! {
    static ref TREE: Mutex<Tree> = Mutex::new(Tree::new());
}

// Global environment for iOS callbacks (BLE events, etc.)
static mut GLOBAL_ENV: Option<Env<'static>> = None;
static mut ENV_INITIALIZED: bool = false;

// ============================================================================
// Helpers
// ============================================================================

fn atom<'a>(env: Env<'a>, name: &str) -> Term<'a> {
    rustler::types::atom::Atom::from_str(env, name)
        .unwrap()
        .to_term(env)
}

fn ok<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    Ok(atom(env, "ok"))
}

fn term_or_error<'a>(env: Env<'a>, opt: Option<Term<'a>>) -> NifResult<Term<'a>> {
    match opt {
        Some(t) => Ok(t),
        None => Ok(atom(env, "error")),
    }
}

// Cache the Erlang environment for use by ObjC callbacks
#[rustler::nif]
fn cache_env<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    unsafe {
        if !ENV_INITIALIZED {
            // Store the environment for later use by callbacks
            GLOBAL_ENV = Some(std::mem::transmute::<Env<'a>, Env<'static>>(env));
            ENV_INITIALIZED = true;
            // Register Bluetooth callbacks
            register_bluetooth_callbacks();
        }
    }
    ok(env)
}

// Register Bluetooth callbacks with Objective-C code
#[cfg(target_os = "ios")]
fn register_bluetooth_callbacks() {
    type BluetoothCallback = unsafe extern "C" fn(*const libc::c_char);

    unsafe extern "C" fn device_found_callback(
        identifier: *const libc::c_char,
        name: *const libc::c_char,
        rssi: libc::c_int,
        advertisement_data: *const libc::c_char,
    ) {
        // Send message to Elixir: {:bluetooth, :device_found, ...}
        eprintln!("[Dala BLE] Device found callback triggered");
        // Full implementation would use erl_nif API to send message to Elixir process
    }

    unsafe extern "C" fn device_connected_callback(identifier: *const libc::c_char) {
        eprintln!("[Dala BLE] Device connected callback triggered");
    }

    unsafe extern "C" fn device_connect_failed_callback(
        identifier: *const libc::c_char,
        error: *const libc::c_char,
    ) {
        eprintln!("[Dala BLE] Device connect failed callback triggered");
    }

    unsafe extern "C" fn device_disconnected_callback(identifier: *const libc::c_char) {
        eprintln!("[Dala BLE] Device disconnected callback triggered");
    }

    // Register callbacks with Objective-C
    extern "C" {
        fn DalaBluetoothSetDeviceFoundCallback(
            callback: unsafe extern "C" fn(
                *const libc::c_char,
                *const libc::c_char,
                libc::c_int,
                *const libc::c_char,
            ),
        );
        fn DalaBluetoothSetDeviceConnectedCallback(
            callback: unsafe extern "C" fn(*const libc::c_char),
        );
        fn DalaBluetoothSetDeviceConnectFailedCallback(
            callback: unsafe extern "C" fn(*const libc::c_char, *const libc::c_char),
        );
        fn DalaBluetoothSetDeviceDisconnectedCallback(
            callback: unsafe extern "C" fn(*const libc::c_char),
        );
    }

    unsafe {
        DalaBluetoothSetDeviceFoundCallback(device_found_callback);
        DalaBluetoothSetDeviceConnectedCallback(device_connected_callback);
        DalaBluetoothSetDeviceConnectFailedCallback(device_connect_failed_callback);
        DalaBluetoothSetDeviceDisconnectedCallback(device_disconnected_callback);
    }
}

#[cfg(not(target_os = "ios"))]
fn register_bluetooth_callbacks() {
    // No-op on non-iOS platforms
}

// Deliver webview eval result to Elixir
#[no_mangle]
pub extern "C" fn dala_deliver_webview_eval_result(json_utf8: *const std::ffi::c_char) {
    unsafe {
        if json_utf8.is_null() {
            return;
        }

        let json = {
            let cstr = std::ffi::CStr::from_ptr(json_utf8);
            match cstr.to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return,
            }
        };

        eprintln!("[Dala] WebView eval result: {}", json);
    }
}

// ============================================================================
// Platform
// ============================================================================

#[rustler::nif]
fn platform<'a>(env: Env<'a>) -> Term<'a> {
    #[cfg(target_os = "ios")]
    return atom(env, "ios");

    #[cfg(target_os = "android")]
    return atom(env, "android");

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    return atom(env, "unknown");
}

// ============================================================================
// Logging
// ============================================================================

#[rustler::nif]
fn log<'a>(env: Env<'a>, msg: Term<'a>) -> NifResult<Term<'a>> {
    let msg_str: String = msg.decode()?;
    platform_log(&msg_str);
    ok(env)
}

#[rustler::nif]
fn log_level<'a>(env: Env<'a>, level: Term<'a>, msg: Term<'a>) -> NifResult<Term<'a>> {
    let level_str: String = level.decode()?;
    let msg_str: String = msg.decode()?;
    platform_log_with_level(&level_str, &msg_str);
    ok(env)
}

// ============================================================================
// UI / Rendering
// ============================================================================

#[rustler::nif]
fn set_transition<'a>(env: Env<'a>, transition: Term<'a>) -> NifResult<Term<'a>> {
    let s: String = transition.decode()?;
    set_transition_internal(&s);
    ok(env)
}

#[rustler::nif]
fn set_root<'a>(env: Env<'a>, json: Term<'a>) -> NifResult<Term<'a>> {
    let json_str: String = json.decode()?;
    let transition = get_transition_and_clear();
    platform_set_root(&json_str, &transition);
    ok(env)
}

#[rustler::nif]
fn set_taps<'a>(env: Env<'a>, _taps: Term<'a>) -> NifResult<Term<'a>> {
    ok(env)
}

#[rustler::nif]
fn register_tap<'a>(env: Env<'a>, _pid: Term<'a>) -> NifResult<Term<'a>> {
    let _handle = register_tap_internal();
    ok(env)
}

#[rustler::nif]
fn clear_taps<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    clear_taps_internal();
    ok(env)
}

#[rustler::nif]
fn exit_app<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_exit_app();
    ok(env)
}

#[rustler::nif]
fn safe_area<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let _insets = platform_safe_area();
    ok(env)
}

// ============================================================================
// Incremental rendering (patch-based)
// ============================================================================

#[rustler::nif]
fn apply_patches<'a>(env: Env<'a>, binary: Binary<'a>) -> NifResult<Term<'a>> {
    let bytes = binary.as_slice();
    let mut tree = TREE
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new("tree lock poisoned")))?;
    decode_and_apply(&mut tree, bytes);
    ok(env)
}

// ============================================================================
// Device APIs — Haptic / Clipboard / Share
// ============================================================================

#[rustler::nif]
fn haptic<'a>(env: Env<'a>, _type: Term<'a>) -> NifResult<Term<'a>> {
    let _t: String = _type.decode()?;
    platform_haptic(&_t);
    ok(env)
}

#[rustler::nif]
fn clipboard_put<'a>(env: Env<'a>, text: Term<'a>) -> NifResult<Term<'a>> {
    let s: String = text.decode()?;
    platform_clipboard_put(&s);
    ok(env)
}

#[rustler::nif]
fn clipboard_get<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let result = platform_clipboard_get(env);
    term_or_error(env, result)
}

#[rustler::nif]
fn share_text<'a>(env: Env<'a>, text: Term<'a>) -> NifResult<Term<'a>> {
    let s: String = text.decode()?;
    platform_share_text(&s);
    ok(env)
}

// ============================================================================
// Permissions
// ============================================================================

#[rustler::nif]
fn request_permission<'a>(env: Env<'a>, _cap: Term<'a>) -> NifResult<Term<'a>> {
    let _cap_str: String = _cap.decode()?;
    ok(env)
}

// ============================================================================
// Biometric
// ============================================================================

#[rustler::nif]
fn biometric_authenticate<'a>(env: Env<'a>, _reason: Term<'a>) -> NifResult<Term<'a>> {
    let _r: String = _reason.decode()?;
    platform_biometric_authenticate(&_r);
    ok(env)
}

// ============================================================================
// Location
// ============================================================================

#[rustler::nif]
fn location_get_once<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let result = platform_location_get_once(env);
    term_or_error(env, result)
}

#[rustler::nif]
fn location_start<'a>(env: Env<'a>, _accuracy: Term<'a>) -> NifResult<Term<'a>> {
    let _a: String = _accuracy.decode()?;
    platform_location_start(&_a);
    ok(env)
}

#[rustler::nif]
fn location_stop<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_location_stop();
    ok(env)
}

// ============================================================================
// Camera
// ============================================================================

#[rustler::nif]
fn camera_capture_photo<'a>(env: Env<'a>, _quality: Term<'a>) -> NifResult<Term<'a>> {
    let _q: String = _quality.decode()?;
    platform_camera_capture_photo(&_q);
    ok(env)
}

#[rustler::nif]
fn camera_capture_video<'a>(env: Env<'a>, _max_duration: Term<'a>) -> NifResult<Term<'a>> {
    let _d: String = _max_duration.decode()?;
    platform_camera_capture_video(&_d);
    ok(env)
}

#[rustler::nif]
fn camera_start_preview<'a>(env: Env<'a>, _opts_json: Term<'a>) -> NifResult<Term<'a>> {
    let _j: String = _opts_json.decode()?;
    platform_camera_start_preview(&_j);
    ok(env)
}

#[rustler::nif]
fn camera_stop_preview<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_camera_stop_preview();
    ok(env)
}

// ============================================================================
// Photos / Files
// ============================================================================

#[rustler::nif]
fn photos_pick<'a>(env: Env<'a>, _max: Term<'a>, _types: Term<'a>) -> NifResult<Term<'a>> {
    let _m: i64 = _max.decode()?;
    let _t: String = _types.decode()?;
    platform_photos_pick(_m as usize, &_t);
    ok(env)
}

#[rustler::nif]
fn files_pick<'a>(env: Env<'a>, _mime_types: Term<'a>) -> NifResult<Term<'a>> {
    let _m: String = _mime_types.decode()?;
    platform_files_pick(&_m);
    ok(env)
}

// ============================================================================
// Audio
// ============================================================================

#[rustler::nif]
fn audio_start_recording<'a>(env: Env<'a>, _opts_json: Term<'a>) -> NifResult<Term<'a>> {
    let _j: String = _opts_json.decode()?;
    platform_audio_start_recording(&_j);
    ok(env)
}

#[rustler::nif]
fn audio_stop_recording<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_audio_stop_recording();
    ok(env)
}

#[rustler::nif]
fn audio_play<'a>(env: Env<'a>, _path: Term<'a>, _opts_json: Term<'a>) -> NifResult<Term<'a>> {
    let _p: String = _path.decode()?;
    let _j: String = _opts_json.decode()?;
    platform_audio_play(&_p, &_j);
    ok(env)
}

#[rustler::nif]
fn audio_stop_playback<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_audio_stop_playback();
    ok(env)
}

#[rustler::nif]
fn audio_set_volume<'a>(env: Env<'a>, _volume: Term<'a>) -> NifResult<Term<'a>> {
    let _v: f64 = _volume.decode()?;
    platform_audio_set_volume(_v);
    ok(env)
}

// ============================================================================
// Motion
// ============================================================================

#[rustler::nif]
fn motion_start<'a>(env: Env<'a>, _sensors: Term<'a>, _interval: Term<'a>) -> NifResult<Term<'a>> {
    let _s: String = _sensors.decode()?;
    let _i: u64 = _interval.decode()?;
    platform_motion_start(&_s, _i);
    ok(env)
}

#[rustler::nif]
fn motion_stop<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_motion_stop();
    ok(env)
}

// ============================================================================
// Scanner
// ============================================================================

#[rustler::nif]
fn scanner_scan<'a>(env: Env<'a>, _formats_json: Term<'a>) -> NifResult<Term<'a>> {
    let _j: String = _formats_json.decode()?;
    platform_scanner_scan(&_j);
    ok(env)
}

// ============================================================================
// Notifications
// ============================================================================

#[rustler::nif]
fn notify_schedule<'a>(env: Env<'a>, _opts_json: Term<'a>) -> NifResult<Term<'a>> {
    let _j: String = _opts_json.decode()?;
    platform_notify_schedule(&_j);
    ok(env)
}

#[rustler::nif]
fn notify_cancel<'a>(env: Env<'a>, _id: Term<'a>) -> NifResult<Term<'a>> {
    let _i: String = _id.decode()?;
    platform_notify_cancel(&_i);
    ok(env)
}

#[rustler::nif]
fn notify_register_push<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_notify_register_push();
    ok(env)
}

#[rustler::nif]
fn take_launch_notification<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let result = platform_take_launch_notification(env);
    term_or_error(env, result)
}

// ============================================================================
// Storage
// ============================================================================

#[rustler::nif]
fn storage_dir<'a>(env: Env<'a>, _location: Term<'a>) -> NifResult<Term<'a>> {
    let _l: String = _location.decode()?;
    let result = platform_storage_dir(env, &_l);
    term_or_error(env, result)
}

#[rustler::nif]
fn storage_save_to_photo_library<'a>(env: Env<'a>, _path: Term<'a>) -> NifResult<Term<'a>> {
    let _p: String = _path.decode()?;
    platform_storage_save_to_photo_library(&_p);
    ok(env)
}

#[rustler::nif]
fn storage_save_to_media_store<'a>(
    env: Env<'a>,
    _path: Term<'a>,
    _type: Term<'a>,
) -> NifResult<Term<'a>> {
    let _p: String = _path.decode()?;
    let _t: String = _type.decode()?;
    platform_storage_save_to_media_store(&_p, &_t);
    ok(env)
}

#[rustler::nif]
fn storage_external_files_dir<'a>(env: Env<'a>, _type: Term<'a>) -> NifResult<Term<'a>> {
    let _t: String = _type.decode()?;
    let result = platform_storage_external_files_dir(env, &_t);
    term_or_error(env, result)
}

// ============================================================================
// Alerts / Overlays
// ============================================================================

#[rustler::nif]
fn alert_show<'a>(
    env: Env<'a>,
    _title: Term<'a>,
    _message: Term<'a>,
    _buttons_json: Term<'a>,
) -> NifResult<Term<'a>> {
    let _t: String = _title.decode()?;
    let _m: String = _message.decode()?;
    let _b: String = _buttons_json.decode()?;
    platform_alert_show(&_t, &_m, &_b);
    ok(env)
}

#[rustler::nif]
fn action_sheet_show<'a>(
    env: Env<'a>,
    _title: Term<'a>,
    _buttons_json: Term<'a>,
) -> NifResult<Term<'a>> {
    let _t: String = _title.decode()?;
    let _b: String = _buttons_json.decode()?;
    platform_action_sheet_show(&_t, &_b);
    ok(env)
}

#[rustler::nif]
fn toast_show<'a>(env: Env<'a>, _message: Term<'a>, _duration: Term<'a>) -> NifResult<Term<'a>> {
    let _m: String = _message.decode()?;
    let _d: String = _duration.decode()?;
    platform_toast_show(&_m, &_d);
    ok(env)
}

// ============================================================================
// WebView
// ============================================================================

#[rustler::nif]
fn webview_eval_js<'a>(env: Env<'a>, _code: Term<'a>) -> NifResult<Term<'a>> {
    let _c: String = _code.decode()?;
    platform_webview_eval_js(&_c);
    ok(env)
}

#[rustler::nif]
fn webview_post_message<'a>(env: Env<'a>, _json: Term<'a>) -> NifResult<Term<'a>> {
    let _j: String = _json.decode()?;
    platform_webview_post_message(&_j);
    ok(env)
}

#[rustler::nif]
fn webview_can_go_back<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let result = platform_webview_can_go_back();
    let atom_name = if result { "true" } else { "false" };
    Ok(atom(env, atom_name))
}

#[rustler::nif]
fn webview_go_back<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_webview_go_back();
    ok(env)
}

#[rustler::nif]
fn webview_screenshot<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    Ok(atom(env, "not_implemented"))
}

// ============================================================================
// Native view components
// ============================================================================

#[rustler::nif]
fn register_component<'a>(env: Env<'a>, _pid: Term<'a>) -> NifResult<Term<'a>> {
    let _handle = register_component_internal();
    ok(env)
}

#[rustler::nif]
fn deregister_component<'a>(env: Env<'a>, _handle: Term<'a>) -> NifResult<Term<'a>> {
    let _h: i64 = _handle.decode()?;
    deregister_component_internal(_h as i32);
    ok(env)
}

// ============================================================================
// Test harness
// ============================================================================

#[rustler::nif]
fn ui_tree<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let result = platform_ui_tree(env);
    term_or_error(env, result)
}

#[rustler::nif]
fn ui_debug<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let result = platform_ui_debug(env);
    term_or_error(env, result)
}

#[rustler::nif]
fn tap<'a>(env: Env<'a>, _label: Term<'a>) -> NifResult<Term<'a>> {
    let _l: String = _label.decode()?;
    platform_tap(&_l);
    ok(env)
}

#[rustler::nif]
fn tap_xy<'a>(env: Env<'a>, _x: Term<'a>, _y: Term<'a>) -> NifResult<Term<'a>> {
    let _xv: f64 = _x.decode()?;
    let _yv: f64 = _y.decode()?;
    platform_tap_xy(_xv, _yv);
    ok(env)
}

#[rustler::nif]
fn type_text<'a>(env: Env<'a>, _text: Term<'a>) -> NifResult<Term<'a>> {
    let _t: String = _text.decode()?;
    platform_type_text(&_t);
    ok(env)
}

#[rustler::nif]
fn delete_backward<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_delete_backward();
    ok(env)
}

#[rustler::nif]
fn key_press<'a>(env: Env<'a>, _key: Term<'a>) -> NifResult<Term<'a>> {
    let _k: String = _key.decode()?;
    platform_key_press(&_k);
    ok(env)
}

#[rustler::nif]
fn clear_text<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_clear_text();
    ok(env)
}

#[rustler::nif]
fn long_press_xy<'a>(
    env: Env<'a>,
    _x: Term<'a>,
    _y: Term<'a>,
    _ms: Term<'a>,
) -> NifResult<Term<'a>> {
    let _xv: f64 = _x.decode()?;
    let _yv: f64 = _y.decode()?;
    let _msv: u64 = _ms.decode()?;
    platform_long_press_xy(_xv, _yv, _msv);
    ok(env)
}

#[rustler::nif]
fn swipe_xy<'a>(
    env: Env<'a>,
    _x1: Term<'a>,
    _y1: Term<'a>,
    _x2: Term<'a>,
    _y2: Term<'a>,
) -> NifResult<Term<'a>> {
    let _x1v: f64 = _x1.decode()?;
    let _y1v: f64 = _y1.decode()?;
    let _x2v: f64 = _x2.decode()?;
    let _y2v: f64 = _y2.decode()?;
    platform_swipe_xy(_x1v, _y1v, _x2v, _y2v);
    ok(env)
}

// ============================================================================
// Bluetooth (BLE)
// ============================================================================

#[rustler::nif]
fn bluetooth_state<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    #[cfg(target_os = "android")]
    {
        // On Android, we need JNIEnv - use the cached JavaVM
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            let state = crate::common::platform_bluetooth_state_with_env(&mut jni_env);
            return Ok(atom(env, Box::leak(state.into_boxed_str())));
        }
    }
    let state = platform_bluetooth_state();
    Ok(atom(env, state))
}

#[rustler::nif]
fn bluetooth_start_scan<'a>(
    env: Env<'a>,
    services: Term<'a>,
    timeout_ms: Term<'a>,
) -> NifResult<Term<'a>> {
    let _services: Vec<String> = services.decode().unwrap_or_default();
    let _timeout: u64 = timeout_ms.decode().unwrap_or(10_000);
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_start_scan_with_env(
                &mut jni_env,
                &_services,
                _timeout,
            );
            return ok(env);
        }
    }
    platform_bluetooth_start_scan(&_services, _timeout);
    ok(env)
}

#[rustler::nif]
fn bluetooth_stop_scan<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_stop_scan_with_env(&mut jni_env);
            return ok(env);
        }
    }
    platform_bluetooth_stop_scan();
    ok(env)
}

#[rustler::nif]
fn bluetooth_connect<'a>(env: Env<'a>, device_id: Term<'a>) -> NifResult<Term<'a>> {
    let _id: String = device_id.decode()?;
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_connect_with_env(&mut jni_env, &_id);
            return ok(env);
        }
    }
    platform_bluetooth_connect(&_id);
    ok(env)
}

#[rustler::nif]
fn bluetooth_disconnect<'a>(env: Env<'a>, device_id: Term<'a>) -> NifResult<Term<'a>> {
    let _id: String = device_id.decode()?;
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_disconnect_with_env(&mut jni_env, &_id);
            return ok(env);
        }
    }
    platform_bluetooth_disconnect(&_id);
    ok(env)
}

#[rustler::nif]
fn bluetooth_discover_services<'a>(env: Env<'a>, device_id: Term<'a>) -> NifResult<Term<'a>> {
    let _id: String = device_id.decode()?;
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_discover_services_with_env(&mut jni_env, &_id);
            return ok(env);
        }
    }
    platform_bluetooth_discover_services(&_id);
    ok(env)
}

#[rustler::nif]
fn bluetooth_read_characteristic<'a>(
    env: Env<'a>,
    device_id: Term<'a>,
    service: Term<'a>,
    characteristic: Term<'a>,
) -> NifResult<Term<'a>> {
    let _id: String = device_id.decode()?;
    let _srv: String = service.decode()?;
    let _chr: String = characteristic.decode()?;
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_read_characteristic_with_env(
                &mut jni_env,
                &_id,
                &_srv,
                &_chr,
            );
            return ok(env);
        }
    }
    platform_bluetooth_read_characteristic(&_id, &_srv, &_chr);
    ok(env)
}

#[rustler::nif]
fn bluetooth_write_characteristic<'a>(
    env: Env<'a>,
    device_id: Term<'a>,
    service: Term<'a>,
    characteristic: Term<'a>,
    value: Term<'a>,
) -> NifResult<Term<'a>> {
    let _id: String = device_id.decode()?;
    let _srv: String = service.decode()?;
    let _chr: String = characteristic.decode()?;
    let _val: Binary = value.decode()?;
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_write_characteristic_with_env(
                &mut jni_env,
                &_id,
                &_srv,
                &_chr,
                _val.as_slice(),
            );
            return ok(env);
        }
    }
    platform_bluetooth_write_characteristic(&_id, &_srv, &_chr, _val.as_slice());
    ok(env)
}

#[rustler::nif]
fn bluetooth_subscribe<'a>(
    env: Env<'a>,
    device_id: Term<'a>,
    service: Term<'a>,
    characteristic: Term<'a>,
) -> NifResult<Term<'a>> {
    let _id: String = device_id.decode()?;
    let _srv: String = service.decode()?;
    let _chr: String = characteristic.decode()?;
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_subscribe_with_env(&mut jni_env, &_id, &_srv, &_chr);
            return ok(env);
        }
    }
    platform_bluetooth_subscribe(&_id, &_srv, &_chr);
    ok(env)
}

#[rustler::nif]
fn bluetooth_unsubscribe<'a>(
    env: Env<'a>,
    device_id: Term<'a>,
    service: Term<'a>,
    characteristic: Term<'a>,
) -> NifResult<Term<'a>> {
    let _id: String = device_id.decode()?;
    let _srv: String = service.decode()?;
    let _chr: String = characteristic.decode()?;
    #[cfg(target_os = "android")]
    {
        if let Some(mut jni_env) = crate::android::get_jni_env() {
            crate::common::platform_bluetooth_unsubscribe_with_env(
                &mut jni_env,
                &_id,
                &_srv,
                &_chr,
            );
            return ok(env);
        }
    }
    platform_bluetooth_unsubscribe(&_id, &_srv, &_chr);
    ok(env)
}

// ============================================================================
// WiFi
// ============================================================================

#[rustler::nif]
fn wifi_current_network<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let result = platform_wifi_current_network(env);
    Ok(result)
}

#[rustler::nif]
fn wifi_scan<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_wifi_scan();
    ok(env)
}

#[rustler::nif]
fn wifi_enable<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_wifi_enable();
    ok(env)
}

#[rustler::nif]
fn wifi_disable<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    platform_wifi_disable();
    ok(env)
}

// ============================================================================
// Initialize NIF
// ============================================================================

rustler::init!("Elixir.Dala.Native");
