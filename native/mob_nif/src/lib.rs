use rustler::{Env, NifResult, Term};
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref CACHED_ENV: Mutex<Option<usize>> = Mutex::new(None);
}

// Platform detection
#[cfg(target_os = "android")]
mod android;
mod common;
#[cfg(target_os = "ios")]
mod ios;

use common::*;

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
    let env_ptr = env.as_c_arg() as usize;
    let mut cached = CACHED_ENV.lock().unwrap();
    *cached = Some(env_ptr);
    ok(env)
}

// Deliver webview eval result to Elixir
// This is called from ObjC when JS evaluation completes
//
// TODO: Properly send message to :mob_screen process:
// 1. Get the :mob_screen pid using erlang:whereis/1 or similar
// 2. Use rustler::env::env_send() to send the tuple
// 3. Message format: {:webview, :eval_result, json_binary}
#[no_mangle]
pub extern "C" fn mob_deliver_webview_eval_result(json_utf8: *const std::ffi::c_char) {
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

        // For now, just log the result
        eprintln!("[Mob] WebView eval result: {}", json);

        // TODO: Send to :mob_screen process
        // let env = ...; // Need to get Env from cached pointer
        // let webview_atom = ...;
        // let eval_result_atom = ...;
        // let json_term = ...;
        // let message = (webview_atom, eval_result_atom, json_term);
        // rustler::env::env_send(&env, pid, message);
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
    // TODO: implement batch tap registration
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
    // On Android, we need JNIEnv - for now just call the stub
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
    // TODO: Capture WebView content as PNG data
    // iOS: Use WKWebView.takeSnapshot()
    // Android: Use WebView.capturePicture() or draw to bitmap
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
    let _m: u64 = _ms.decode()?;
    platform_long_press_xy(_xv, _yv, _m);
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
// Initialize NIF
// ============================================================================

rustler::init!(
    "Elixir.Mob.Native",
    [
        cache_env,
        platform,
        log,
        log_level,
        set_transition,
        set_root,
        set_taps,
        register_tap,
        clear_taps,
        exit_app,
        safe_area,
        haptic,
        clipboard_put,
        clipboard_get,
        share_text,
        request_permission,
        biometric_authenticate,
        location_get_once,
        location_start,
        location_stop,
        camera_capture_photo,
        camera_capture_video,
        camera_start_preview,
        camera_stop_preview,
        photos_pick,
        files_pick,
        audio_start_recording,
        audio_stop_recording,
        audio_play,
        audio_stop_playback,
        audio_set_volume,
        motion_start,
        motion_stop,
        scanner_scan,
        notify_schedule,
        notify_cancel,
        notify_register_push,
        take_launch_notification,
        storage_dir,
        storage_save_to_photo_library,
        storage_save_to_media_store,
        storage_external_files_dir,
        alert_show,
        action_sheet_show,
        toast_show,
        webview_eval_js,
        webview_post_message,
        webview_can_go_back,
        webview_go_back,
        webview_screenshot,
        register_component,
        deregister_component,
        ui_tree,
        ui_debug,
        tap,
        tap_xy,
        type_text,
        delete_backward,
        key_press,
        clear_text,
        long_press_xy,
        swipe_xy
    ]
);
