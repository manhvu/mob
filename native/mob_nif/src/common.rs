// common.rs - Shared types and platform dispatch

use rustler::{Env, Term};
use std::sync::Mutex;

// Safe area insets
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub struct SafeArea {
    pub top: f64,
    pub bottom: f64,
    pub left: f64,
    pub right: f64,
}

// Transition state
lazy_static::lazy_static! {
    static ref TRANSITION: Mutex<String> = Mutex::new("none".to_string());
}

// Tap handle registry
const MAX_TAP_HANDLES: usize = 256;

#[derive(Clone, Copy)]
struct TapHandle {
    active: bool,
}

impl Default for TapHandle {
    fn default() -> Self {
        TapHandle { active: false }
    }
}

lazy_static::lazy_static! {
    static ref TAP_HANDLES: Mutex<[TapHandle; MAX_TAP_HANDLES]> =
        Mutex::new([TapHandle::default(); MAX_TAP_HANDLES]);
    static ref TAP_HANDLE_NEXT: Mutex<usize> = Mutex::new(0);
}

// Component handle registry
const MAX_COMPONENT_HANDLES: usize = 64;

#[derive(Clone, Copy)]
struct ComponentHandle {
    active: bool,
}

impl Default for ComponentHandle {
    fn default() -> Self {
        ComponentHandle { active: false }
    }
}

lazy_static::lazy_static! {
    static ref COMPONENT_HANDLES: Mutex<[ComponentHandle; MAX_COMPONENT_HANDLES]> =
        Mutex::new([ComponentHandle::default(); MAX_COMPONENT_HANDLES]);
    static ref COMPONENT_HANDLE_NEXT: Mutex<usize> = Mutex::new(0);
}

// ============================================================================
// Public functions — transition
// ============================================================================

pub fn set_transition_internal(transition: &str) {
    let mut t = TRANSITION.lock().unwrap();
    *t = transition.to_string();
}

#[allow(dead_code)]
pub fn get_transition_and_clear() -> String {
    let mut t = TRANSITION.lock().unwrap();
    let result = t.clone();
    *t = "none".to_string();
    result
}

// ============================================================================
// Public functions — set_root (UI update)
// ============================================================================

pub fn platform_set_root(_json: &str, _transition: &str) {
    #[cfg(target_os = "ios")]
    ios::set_root(_json, _transition);

    #[cfg(target_os = "android")]
    super::android::set_root(_json, _transition);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] set_root({}) stub", _json);
}

// ============================================================================
// Public functions — tap registry
// ============================================================================

pub fn register_tap_internal() -> i32 {
    let mut next = TAP_HANDLE_NEXT.lock().unwrap();
    let mut handles = TAP_HANDLES.lock().unwrap();

    if *next >= MAX_TAP_HANDLES {
        return -1;
    }

    handles[*next].active = true;
    let handle = *next as i32;
    *next += 1;
    handle
}

pub fn clear_taps_internal() {
    let mut next = TAP_HANDLE_NEXT.lock().unwrap();
    let mut handles = TAP_HANDLES.lock().unwrap();

    for i in 0..*next {
        handles[i].active = false;
    }
    *next = 0;
}

// ============================================================================
// Public functions — component registry
// ============================================================================

pub fn register_component_internal() -> i32 {
    let mut next = COMPONENT_HANDLE_NEXT.lock().unwrap();
    let mut handles = COMPONENT_HANDLES.lock().unwrap();

    if *next >= MAX_COMPONENT_HANDLES {
        return -1;
    }

    handles[*next].active = true;
    let handle = *next as i32;
    *next += 1;
    handle
}

pub fn deregister_component_internal(handle: i32) {
    let mut handles = COMPONENT_HANDLES.lock().unwrap();
    if handle >= 0 && (handle as usize) < MAX_COMPONENT_HANDLES {
        handles[handle as usize].active = false;
    }
}

// ============================================================================
// Platform dispatch — logging
// ============================================================================

pub fn platform_log(msg: &str) {
    #[cfg(target_os = "ios")]
    ios::log(msg);

    #[cfg(target_os = "android")]
    super::android::log(msg);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] {}", msg);
}

pub fn platform_log_with_level(level: &str, msg: &str) {
    let _full = format!("[{}] {}", level, msg);

    #[cfg(target_os = "ios")]
    ios::log_with_level(level, msg);

    #[cfg(target_os = "android")]
    super::android::log_with_level(level, msg);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob]{}", _full);
}

// ============================================================================
// Platform dispatch — app lifecycle
// ============================================================================

pub fn platform_exit_app() {
    #[cfg(target_os = "ios")]
    ios::exit_app();

    #[cfg(target_os = "android")]
    super::android::exit_app();

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] exit_app called (stub)");
}

pub fn platform_safe_area() -> SafeArea {
    #[cfg(target_os = "ios")]
    return ios::safe_area();

    #[cfg(target_os = "android")]
    return super::android::safe_area();

    SafeArea {
        top: 0.0,
        bottom: 0.0,
        left: 0.0,
        right: 0.0,
    }
}

// ============================================================================
// Platform dispatch — device APIs
// ============================================================================

pub fn platform_haptic(_type: &str) {
    #[cfg(target_os = "ios")]
    ios::haptic(_type);

    #[cfg(target_os = "android")]
    super::android::haptic(_type);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] haptic({}) called (stub)", _type);
}

pub fn platform_clipboard_put(text: &str) {
    #[cfg(target_os = "ios")]
    ios::clipboard_put(text);

    #[cfg(target_os = "android")]
    super::android::clipboard_put(text);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] clipboard_put({}) called (stub)", text);
}

pub fn platform_clipboard_get<'a>(_env: Env<'a>) -> Option<Term<'a>> {
    #[cfg(target_os = "ios")]
    return ios::clipboard_get();

    #[cfg(target_os = "android")]
    return super::android::clipboard_get(_env);

    None
}

pub fn platform_share_text(text: &str) {
    #[cfg(target_os = "ios")]
    ios::share_text(text);

    #[cfg(target_os = "android")]
    super::android::share_text(text);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] share_text({}) stub", text);
}

// ============================================================================
// Platform dispatch — biometric / permissions
// ============================================================================

pub fn platform_biometric_authenticate(_reason: &str) {
    println!("[Mob] biometric_authenticate stub");
}

pub fn platform_request_permission(_cap: &str) {
    println!("[Mob] request_permission({}) stub", _cap);
}

// ============================================================================
// Platform dispatch — location
// ============================================================================

pub fn platform_location_get_once<'a>(_env: Env<'a>) -> Option<Term<'a>> {
    None
}

pub fn platform_location_start(_accuracy: &str) {
    println!("[Mob] location_start({}) stub", _accuracy);
}

pub fn platform_location_stop() {
    println!("[Mob] location_stop stub");
}

// ============================================================================
// Platform dispatch — camera
// ============================================================================

pub fn platform_camera_capture_photo(_quality: &str) {
    println!("[Mob] camera_capture_photo({}) stub", _quality);
}

pub fn platform_camera_capture_video(_max_duration: &str) {
    println!("[Mob] camera_capture_video({}) stub", _max_duration);
}

pub fn platform_camera_start_preview(_opts_json: &str) {
    println!("[Mob] camera_start_preview stub");
}

pub fn platform_camera_stop_preview() {
    println!("[Mob] camera_stop_preview stub");
}

// ============================================================================
// Platform dispatch — photos / files
// ============================================================================

pub fn platform_photos_pick(_max: usize, _types: &str) {
    println!("[Mob] photos_pick stub");
}

pub fn platform_files_pick(_mime_types: &str) {
    println!("[Mob] files_pick stub");
}

// ============================================================================
// Platform dispatch — audio
// ============================================================================

pub fn platform_audio_start_recording(_opts_json: &str) {
    println!("[Mob] audio_start_recording stub");
}

pub fn platform_audio_stop_recording() {
    println!("[Mob] audio_stop_recording stub");
}

pub fn platform_audio_play(_path: &str, _opts_json: &str) {
    println!("[Mob] audio_play stub");
}

pub fn platform_audio_stop_playback() {
    println!("[Mob] audio_stop_playback stub");
}

pub fn platform_audio_set_volume(_volume: f64) {
    println!("[Mob] audio_set_volume({}) stub", _volume);
}

// ============================================================================
// Platform dispatch — motion
// ============================================================================

pub fn platform_motion_start(_sensors: &str, _interval: u64) {
    println!("[Mob] motion_start stub");
}

pub fn platform_motion_stop() {
    println!("[Mob] motion_stop stub");
}

// ============================================================================
// Platform dispatch — scanner
// ============================================================================

pub fn platform_scanner_scan(_formats_json: &str) {
    println!("[Mob] scanner_scan stub");
}

// ============================================================================
// Platform dispatch — notifications
// ============================================================================

pub fn platform_notify_schedule(_opts_json: &str) {
    println!("[Mob] notify_schedule stub");
}

pub fn platform_notify_cancel(_id: &str) {
    println!("[Mob] notify_cancel({}) stub", _id);
}

pub fn platform_notify_register_push() {
    println!("[Mob] notify_register_push stub");
}

pub fn platform_take_launch_notification<'a>(_env: Env<'a>) -> Option<Term<'a>> {
    None
}

// ============================================================================
// Platform dispatch — storage
// ============================================================================

pub fn platform_storage_dir<'a>(_env: Env<'a>, _location: &str) -> Option<Term<'a>> {
    None
}

pub fn platform_storage_save_to_photo_library(_path: &str) {
    println!("[Mob] storage_save_to_photo_library stub");
}

pub fn platform_storage_save_to_media_store(_path: &str, _type: &str) {
    println!("[Mob] storage_save_to_media_store stub");
}

pub fn platform_storage_external_files_dir<'a>(_env: Env<'a>, _type: &str) -> Option<Term<'a>> {
    None
}

// ============================================================================
// Platform dispatch — alerts / overlays
// ============================================================================

pub fn platform_alert_show(_title: &str, _message: &str, _buttons_json: &str) {
    println!("[Mob] alert_show stub");
}

pub fn platform_action_sheet_show(_title: &str, _buttons_json: &str) {
    println!("[Mob] action_sheet_show stub");
}

pub fn platform_toast_show(_message: &str, _duration: &str) {
    println!("[Mob] toast_show stub");
}

// ============================================================================
// Platform dispatch — WebView
// ============================================================================

pub fn platform_webview_eval_js(_code: &str) {
    println!("[Mob] webview_eval_js stub");
}

pub fn platform_webview_post_message(_json: &str) {
    println!("[Mob] webview_post_message stub");
}

pub fn platform_webview_can_go_back() -> bool {
    false
}

pub fn platform_webview_go_back() {
    println!("[Mob] webview_go_back stub");
}

// ============================================================================
// Platform dispatch — test harness
// ============================================================================

pub fn platform_ui_tree<'a>(_env: Env<'a>) -> Option<Term<'a>> {
    #[cfg(target_os = "ios")]
    return ios::ui_tree();

    #[cfg(target_os = "android")]
    return super::android::ui_tree(_env);

    None
}

pub fn platform_ui_debug<'a>(_env: Env<'a>) -> Option<Term<'a>> {
    #[cfg(target_os = "ios")]
    return ios::ui_debug();

    #[cfg(target_os = "android")]
    return super::android::ui_debug(_env);

    None
}

pub fn platform_tap(_label: &str) {
    #[cfg(target_os = "ios")]
    ios::tap(_label);

    #[cfg(target_os = "android")]
    super::android::tap(_label);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] tap({}) stub", _label);
}

pub fn platform_tap_xy(_x: f64, _y: f64) {
    #[cfg(target_os = "ios")]
    ios::tap_xy(_x, _y);

    #[cfg(target_os = "android")]
    super::android::tap_xy(_x, _y);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] tap_xy({}, {}) stub", _x, _y);
}

pub fn platform_type_text(_text: &str) {
    #[cfg(target_os = "ios")]
    ios::type_text(_text);

    #[cfg(target_os = "android")]
    super::android::type_text(_text);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] type_text({}) stub", _text);
}

pub fn platform_delete_backward() {
    #[cfg(target_os = "ios")]
    ios::delete_backward();

    #[cfg(target_os = "android")]
    super::android::delete_backward();

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] delete_backward stub");
}

pub fn platform_key_press(_key: &str) {
    println!("[Mob] key_press({}) stub", _key);
}

pub fn platform_clear_text() {
    #[cfg(target_os = "ios")]
    ios::clear_text();

    #[cfg(target_os = "android")]
    super::android::clear_text();

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] clear_text stub");
}

pub fn platform_long_press_xy(_x: f64, _y: f64, _ms: u64) {
    #[cfg(target_os = "ios")]
    ios::long_press_xy(_x, _y, _ms);

    #[cfg(target_os = "android")]
    super::android::long_press_xy(_x, _y, _ms);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] long_press_xy stub");
}

pub fn platform_swipe_xy(_x1: f64, _y1: f64, _x2: f64, _y2: f64) {
    #[cfg(target_os = "ios")]
    ios::swipe_xy(_x1, _y1, _x2, _y2);

    #[cfg(target_os = "android")]
    super::android::swipe_xy(_x1, _y1, _x2, _y2);

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    println!("[Mob] swipe_xy stub");
}

// ============================================================================
// JSON parsing helper
// ============================================================================

#[allow(dead_code)]
pub fn parse_json(_json: &str) -> Result<(), String> {
    Ok(())
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transition_set_and_clear() {
        set_transition_internal("slide");
        let t = get_transition_and_clear();
        assert_eq!(t, "slide");

        let empty = get_transition_and_clear();
        assert_eq!(empty, "none");
    }

    #[test]
    fn test_tap_registry() {
        clear_taps_internal();

        let h1 = register_tap_internal();
        assert!(h1 >= 0);

        let h2 = register_tap_internal();
        assert!(h2 >= 0);
        assert_ne!(h1, h2);

        clear_taps_internal();
    }

    #[test]
    fn test_component_registry() {
        let h1 = register_component_internal();
        assert!(h1 >= 0);

        deregister_component_internal(h1);
    }

    #[test]
    fn test_safe_area_values() {
        let a = platform_safe_area();
        // Just verify it doesn't panic
        let _ = a.top;
        let _ = a.bottom;
    }
}
