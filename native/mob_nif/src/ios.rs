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
    unsafe {
        let mut insets = objc::runtime::UIEdgeInsets {
            top: 0.0,
            left: 0.0,
            bottom: 0.0,
            right: 0.0,
        };

        // Dispatch to main thread to access UIWindow
        let block: extern "C" fn(*mut Object, *mut Object) -> *mut Object =
            unsafe { std::mem::transmute(safe_area_block as usize) };
        let queue: *mut Object = msg_send![class!(dispatch_get_main_queue)];
        let _: () =
            msg_send![queue, dispatch_sync: block, context: &mut insets as *mut _ as *mut Object];

        super::common::SafeArea {
            top: insets.top as f64,
            bottom: insets.bottom as f64,
            left: insets.left as f64,
            right: insets.right as f64,
        }
    }
}

extern "C" fn safe_area_block(_block: *mut Object, context: *mut Object) {
    unsafe {
        let insets_ptr = context as *mut objc::runtime::UIEdgeInsets;
        let mut window: *mut Object = std::ptr::null_mut();

        // Iterate over connected scenes to find UIWindowScene
        let scenes: *mut Object = msg_send![
            msg_send![class!(UIApplication), sharedApplication],
            connectedScenes
        ];
        let count: usize = msg_send![scenes, count];

        for i in 0..count {
            let scene: *mut Object = msg_send![scenes, objectAtIndex: i];
            let class: *const objc::runtime::Class = msg_send![scene, class];
            if class != class!(UIWindowScene) {
                continue;
            }
            let ws: *mut Object = scene as *mut Object; // UIWindowScene
            let windows: *mut Object = msg_send![ws, windows];
            let first: *mut Object = msg_send![windows, firstObject];
            if !first.is_null() {
                window = first;
                break;
            }
        }

        if !window.is_null() {
            let insets: UIEdgeInsets = msg_send![window, safeAreaInsets];
            (*insets_ptr) = insets;
        }
    }
}

// ============================================================================
// UI Tree (test harness)
// ============================================================================

pub fn ui_tree() -> Option<String> {
    unsafe {
        // Call MobViewModel.shared.uiTree() which returns NSString*
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
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
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
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
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, tapAtX: x, y: y];
    }
}

pub fn tap(label: &str) {
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
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
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
        if vm.is_null() {
            return;
        }
        let ns_text = ns_string_from_str(text);
        let _: () = msg_send![vm, typeText: ns_text];
    }
}

pub fn delete_backward() {
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, deleteBackward];
    }
}

pub fn clear_text() {
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, clearText];
    }
}

pub fn long_press_xy(x: f64, y: f64, _ms: u64) {
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
        if vm.is_null() {
            return;
        }
        let _: () = msg_send![vm, longPressAtX: x, y: y];
    }
}

pub fn swipe_xy(x1: f64, y1: f64, x2: f64, y2: f64) {
    unsafe {
        let vm: *mut Object = msg_send![class!(MobViewModel), shared];
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
    unsafe {
        let ns_type = ns_string_from_str(_type);
        let _: () = msg_send![class!(MobViewModel), haptic: ns_type];
    }
}

// ============================================================================
// Clipboard
// ============================================================================

pub fn clipboard_put(text: &str) {
    unsafe {
        let ns_text = ns_string_from_str(text);
        let pasteboard: *mut Object = msg_send![class!(UIPasteboard), generalPasteboard];
        let _: () = msg_send![pasteboard, setString: ns_text];
    }
}

pub fn clipboard_get() -> Option<String> {
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
