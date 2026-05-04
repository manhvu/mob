// android.rs - Android-specific NIF implementations using JNI

use jni::objects::JClass;
use jni::JNIEnv;

// Helper: get the MobBridge class
unsafe fn get_bridge_class<'a>(env: &mut JNIEnv<'a>) -> Option<JClass<'a>> {
    match env.find_class("com/example/mob/MobBridge") {
        Ok(c) => Some(c),
        Err(_) => None,
    }
}

// Helper: call a void method on MobBridge
unsafe fn call_bridge_void<'a>(
    env: &mut JNIEnv<'a>,
    method: &str,
    sig: &str,
    args: &[jni::objects::JValue<'a, 'a>],
) {
    if let Some(class) = get_bridge_class(env) {
        let _ = env.call_static_method(class, method, sig, args);
    }
}

// ============================================================================
// Platform
// ============================================================================

#[allow(dead_code)]
pub fn platform() -> &'static str {
    "android"
}

// ============================================================================
// Logging
// ============================================================================

pub fn log(msg: &str) {
    // Use stderr which appears in logcat on Android
    eprintln!("[Mob] {}", msg);
}

pub fn log_with_level(level: &str, msg: &str) {
    let _full = format!("[{}] {}", level, msg);
    log(&_full);
}

// ============================================================================
// App lifecycle
// ============================================================================

pub fn exit_app() {
    // Stub - requires JNIEnv from JavaVM
    eprintln!("[Mob] exit_app called (stub)");
}

// ============================================================================
// Safe area
// ============================================================================

pub fn safe_area() -> super::common::SafeArea {
    // Stub - requires JNIEnv from JavaVM
    super::common::SafeArea {
        top: 0.0,
        bottom: 0.0,
        left: 0.0,
        right: 0.0,
    }
}

// ============================================================================
// UI Tree (test harness)
// ============================================================================

pub fn ui_tree<'a>(_env: rustler::Env<'a>) -> Option<rustler::Term<'a>> {
    // Stub - requires JNIEnv from JavaVM
    None
}

pub fn ui_debug<'a>(_env: rustler::Env<'a>) -> Option<rustler::Term<'a>> {
    // Stub - requires JNIEnv from JavaVM
    None
}

// ============================================================================
// Tap / Touch
// ============================================================================

pub fn tap_xy(_x: f64, _y: f64) {
    // Stub - requires JNIEnv from JavaVM
}

pub fn tap(_label: &str) {
    // Stub - requires JNIEnv from JavaVM
}

// ============================================================================
// Keyboard
// ============================================================================

pub fn type_text(_text: &str) {
    // Stub - requires JNIEnv from JavaVM
}

pub fn delete_backward() {
    // Stub - requires JNIEnv from JavaVM
}

pub fn clear_text() {
    // Stub - requires JNIEnv from JavaVM
}

pub fn long_press_xy(_x: f64, _y: f64, _ms: u64) {
    // Stub - requires JNIEnv from JavaVM
}

pub fn swipe_xy(_x1: f64, _y1: f64, _x2: f64, _y2: f64) {
    // Stub - requires JNIEnv from JavaVM
}

// ============================================================================
// Haptic
// ============================================================================

pub fn haptic(_type: &str) {
    // Stub - requires JNIEnv from JavaVM
}

// ============================================================================
// Clipboard
// ============================================================================

pub fn clipboard_put(_text: &str) {
    // Stub - requires JNIEnv from JavaVM
}

pub fn clipboard_get<'a>(_env: rustler::Env<'a>) -> Option<rustler::Term<'a>> {
    // Stub - requires JNIEnv from JavaVM
    None
}

// ============================================================================
// Share
// ============================================================================

pub fn share_text(_text: &str) {
    // Stub - requires JNIEnv from JavaVM
}

// ============================================================================
// WebView
// ============================================================================
// Note: Android WebView operations require JNIEnv from JavaVM.
// These functions are called from NIFs that have access to JNIEnv.

pub fn webview_eval_js(env: &mut JNIEnv, code: &str) {
    if let Some(class) = get_bridge_class(env) {
        let method = "evaluateJavascript";
        let sig = "(Ljava/lang/String;)V";
        if let Ok(code_jstring) = env.new_string(code) {
            let args = [jni::objects::JValue::Object(code_jstring.into())];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

pub fn webview_post_message(env: &mut JNIEnv, json: &str) {
    if let Some(class) = get_bridge_class(env) {
        let method = "postMessage";
        let sig = "(Ljava/lang/String;)V";
        if let Ok(json_jstring) = env.new_string(json) {
            let args = [jni::objects::JValue::Object(json_jstring.into())];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

pub fn webview_can_go_back(env: &mut JNIEnv) -> bool {
    if let Some(class) = get_bridge_class(env) {
        let method = "canGoBack";
        let sig = "()Z";
        if let Ok(val) = env.call_static_method(class, method, sig, &[]) {
            if let Ok(b) = val.z() {
                return b != 0;
            }
        }
    }
    false
}

pub fn webview_go_back(env: &mut JNIEnv) {
    if let Some(class) = get_bridge_class(env) {
        let method = "goBack";
        let sig = "()V";
        let _ = env.call_static_method(class, method, sig, &[]);
    }
}

pub fn webview_screenshot(_env: &mut JNIEnv) -> bool {
    // TODO: Capture WebView content as PNG
    // 1. Get WebView instance from MobBridge
    // 2. Call drawing cache or PixelCopy (API 26+)
    // 3. Compress to PNG and return data
    eprintln!("[Mob] webview_screenshot not yet implemented");
    false
}
