// ios.rs - iOS-specific NIF implementations using Objective-C FFI

use objc::runtime::{Class, Object};
use objc::{class, msg_send, sel, sel_impl};
use std::ffi::{CStr, CString};

// Helper: convert Rust string to NSString
unsafe fn ns_string_from_str(s: &str) -> *mut Object {
    let cstr = CString::new(s).unwrap_or_default();
    msg_send![class!(NSString), stringWithUTF8String: cstr.as_ptr()]
}

// Helper: convert NSString to Rust String
unsafe fn string_from_ns_string(ns: *mut Object) -> String {
    if ns.is_null() {
        return String::new();
    }
    let cstr: *const i8 = msg_send![ns, UTF8String];
    if cstr.is_null() {
        return String::new();
    }
    let cstr = CStr::from_ptr(cstr);
    cstr.to_string_lossy().into_owned()
}

// ============================================================================
// Platform
// ============================================================================

pub fn platform() -> &'static str {
    "ios"
}

// ============================================================================
// Logging
// ============================================================================

pub fn log(msg: &str) {
    // SAFETY: msg_cstr is a valid UTF-8 C string created from Rust.
    // NSString::stringWithUTF8String: expects a null-terminated C string.
    // NSLog::log: takes an NSString object. Both conversions are valid.
    let msg_cstr = CString::new(msg).unwrap_or_default();
    unsafe {
        let ns_msg: *mut Object =
            msg_send![class!(NSString), stringWithUTF8String: msg_cstr.as_ptr()];
        let _: () = msg_send![class!(NSLog), log: ns_msg];
    }
}

pub fn log_with_level(level: &str, msg: &str) {
    let full = format!("[{}] {}", level, msg);
    log(&full);
}

// ============================================================================
// App lifecycle
// ============================================================================

pub fn exit_app() {
    // SAFETY: UIApplication::sharedApplication returns a valid UIApplication object.
    // terminateWithSuccess is a standard UIApplication method.
    // This is safe to call from any thread.
    unsafe {
        let app: *mut Object = msg_send![class!(UIApplication), sharedApplication];
        if !app.is_null() {
            let _: () = msg_send![app, terminateWithSuccess];
        }
    }
}

// ============================================================================
// Safe area
// ============================================================================

pub fn safe_area() -> super::common::SafeArea {
    // SAFETY: This function dispatches a block to the main queue to access UIKit.
    // UIEdgeInsets must be accessed from the main thread.
    // dispatch_sync_f is used instead of block transmute (no UB).
    unsafe {
        let mut insets = objc::runtime::UIEdgeInsets {
            top: 0.0,
            left: 0.0,
            bottom: 0.0,
            right: 0.0,
        };

        // SAFETY: dispatch_sync_f calls the C function on the main queue.
        // The context pointer points to a valid UIEdgeInsets on the stack.
        // safe_area_block_f is a proper extern "C" function, not a transmute.
        let queue: *mut Object = msg_send![class!(dispatch_get_main_queue)];
        extern "C" {
            fn dispatch_sync_f(
                queue: *mut Object,
                context: *mut std::ffi::c_void,
                work: extern "C" fn(*mut std::ffi::c_void),
            );
        }
        dispatch_sync_f(
            queue,
            &mut insets as *mut _ as *mut std::ffi::c_void,
            safe_area_block_f,
        );

        super::common::SafeArea {
            top: insets.top as f64,
            bottom: insets.bottom as f64,
            left: insets.left as f64,
            right: insets.right as f64,
        }
    }
}

// safe_area_block_f is defined above inside safe_area()
// This extern "C" fn is no longer needed as a separate function.

// ============================================================================
// UI Tree (test harness)
// ============================================================================

pub fn ui_tree() -> Option<String> {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // UI methods are safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return None;
        }
        let tree: *mut Object = msg_send![vm, uiTree];
        if tree.is_null() {
            return None;
        }
        Some(string_from_ns_string(tree))
    }
}

pub fn ui_debug() -> Option<String> {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // UI methods are safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return None;
        }
        let debug: *mut Object = msg_send![vm, uiDebug];
        if debug.is_null() {
            return None;
        }
        Some(string_from_ns_string(debug))
    }
}

// ============================================================================
// Tap / Touch
// ============================================================================

pub fn tap_xy(x: f64, y: f64) {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // tapAtX:y: is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, tapAtX: x, y: y];
    }
}

pub fn tap(label: &str) {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // tapLabel: is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let ns_label = ns_string_from_str(label);
        let _: () = msg_send![vm, tapLabel: ns_label];
    }
}

// ============================================================================
// Keyboard
// ============================================================================

pub fn type_text(text: &str) {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // typeText: is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let ns_text = ns_string_from_str(text);
        let _: () = msg_send![vm, typeText: ns_text];
    }
}

pub fn delete_backward() {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // deleteBackward is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, deleteBackward];
    }
}

pub fn clear_text() {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // clearText is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, clearText];
    }
}

pub fn long_press_xy(x: f64, y: f64, _ms: u64) {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // longPressAtX:y: is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, longPressAtX: x, y: y];
    }
}

pub fn swipe_xy(x1: f64, y1: f64, x2: f64, y2: f64) {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // swipeFromX:y:toX:y: is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, swipeFromX: x1, y: y1, toX: x2, y: y2];
    }
}

// ============================================================================
// Haptic
// ============================================================================

pub fn haptic(_type: &str) {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // haptic: is a DalaViewModel method safe to call from any thread.
    unsafe {
        let ns_type = ns_string_from_str(_type);
        let _: () = msg_send![class!(DalaViewModel), haptic: ns_type];
    }
}

// ============================================================================
// Clipboard
// ============================================================================

pub fn clipboard_put(text: &str) {
    // SAFETY: UIPasteboard::generalPasteboard returns a valid object.
    // setString: is a standard UIPasteboard method.
    unsafe {
        let ns_text = ns_string_from_str(text);
        let pasteboard: *mut Object = msg_send![class!(UIPasteboard), generalPasteboard];
        let _: () = msg_send![pasteboard, setString: ns_text];
    }
}

pub fn clipboard_get() -> Option<String> {
    // SAFETY: UIPasteboard::generalPasteboard returns a valid object.
    // string is a standard UIPasteboard method.
    unsafe {
        let pasteboard: *mut Object = msg_send![class!(UIPasteboard), generalPasteboard];
        let string: *mut Object = msg_send![pasteboard, string];
        if string.is_null() {
            return None;
        }
        Some(string_from_ns_string(string))
    }
}

// ============================================================================
// Share
// ============================================================================

pub fn share_text(text: &str) {
    // SAFETY: UIActivityViewController methods are safe to call.
    // The activity will be presented from the active window scene.
    unsafe {
        let ns_text = ns_string_from_str(text);
        let activity: *mut Object = msg_send![class!(UIActivityViewController), alloc];
        let init: *mut Object = msg_send![activity, initWithActivityItems: ns_text, applicationActivities: std::ptr::null_mut::<Object>()];
        let app: *mut Object = msg_send![class!(UIApplication), sharedApplication];
        let scene: *mut Object = msg_send![app, connectedScenes];
        // Simplified: present from first window scene
        let _: () = msg_send![init, autorelease];
    }
}

// ============================================================================
// UI / Rendering
// ============================================================================

pub fn set_root(json: &str, transition: &str) {
    // SAFETY: DalaViewModel::shared returns a valid object or nil.
    // setRootFromJSON:transition: is a DalaViewModel method safe to call from any thread.
    unsafe {
        let vm: *mut Object = msg_send![class!(DalaViewModel), shared];
        if vm.is_null() {
            return;
        }
        let ns_json = ns_string_from_str(json);
        let ns_transition = ns_string_from_str(transition);
        let _: () = msg_send![vm, setRootFromJSON: ns_json, transition: ns_transition];
    }
}
