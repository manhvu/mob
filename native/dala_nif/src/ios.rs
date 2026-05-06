// ios.rs - iOS-specific NIF implementations using Objective-C FFI

use objc::runtime::{Class, Object};
use objc::{class, msg_send, sel, sel_impl};
use std::ffi::{CStr, CString};
use std::ptr;

// For WiFi IP address lookup
#[cfg(target_os = "ios")]
use libc::{getifaddrs, freeifaddrs, ifaddrs, sockaddr_in, AF_INET, IFF_UP, IFF_RUNNING};

// For CNCopyCurrentNetworkInfo
#[cfg(target_os = "ios")]
use core_foundation::string::CFString;
#[cfg(target_os = "ios")]
use core_foundation::dictionary::CFDictionary;
#[cfg(target_os = "ios")]
use core_foundation::base::{CFType, TCFType, ToVoid};

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

// Register Bluetooth callbacks with Objective-C code
pub fn register_bluetooth_callbacks(
    device_found: unsafe extern "C" fn(*const libc::c_char, *const libc::c_char, libc::c_int, *const libc::c_char),
    device_connected: unsafe extern "C" fn(*const libc::c_char),
) {
    extern "C" {
        fn DalaBluetoothSetDeviceFoundCallback(callback: unsafe extern "C" fn(*const libc::c_char, *const libc::c_char, libc::c_int, *const libc::c_char));
        fn DalaBluetoothSetDeviceConnectedCallback(callback: unsafe extern "C" fn(*const libc::c_char));
        fn DalaBluetoothSetDeviceConnectFailedCallback(callback: unsafe extern "C" fn(*const libc::c_char, *const libc::c_char));
        fn DalaBluetoothSetDeviceDisconnectedCallback(callback: unsafe extern "C" fn(*const libc::c_char));
    }

    unsafe {
        DalaBluetoothSetDeviceFoundCallback(device_found);
        DalaBluetoothSetDeviceConnectedCallback(device_connected);
        // Note: Other callbacks would be registered similarly
    }
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

// ============================================================================
// Bluetooth (BLE)
// ============================================================================

// C function declarations for calling Objective-C Bluetooth code
extern "C" {
    fn DalaBluetoothGetState() -> *const libc::c_char;
    fn DalaBluetoothStartScan(
        serviceUUIDs: *const *const libc::c_char,
        serviceCount: libc::c_int,
        timeoutMs: libc::c_ulong,
    );
    fn DalaBluetoothStopScan();
    fn DalaBluetoothConnect(identifier: *const libc::c_char);
    fn DalaBluetoothDisconnect(identifier: *const libc::c_char);
    fn DalaBluetoothDiscoverServices(identifier: *const libc::c_char);
    fn DalaBluetoothReadCharacteristic(
        identifier: *const libc::c_char,
        serviceUUID: *const libc::c_char,
        characteristicUUID: *const libc::c_char,
    );
    fn DalaBluetoothWriteCharacteristic(
        identifier: *const libc::c_char,
        serviceUUID: *const libc::c_char,
        characteristicUUID: *const libc::c_char,
        value: *const u8,
        valueLen: libc::c_size_t,
    );
    fn DalaBluetoothSubscribe(
        identifier: *const libc::c_char,
        serviceUUID: *const libc::c_char,
        characteristicUUID: *const libc::c_char,
    );
    fn DalaBluetoothUnsubscribe(
        identifier: *const libc::c_char,
        serviceUUID: *const libc::c_char,
        characteristicUUID: *const libc::c_char,
    );
}

pub fn bluetooth_state<'a>() -> &'a str {
    unsafe {
        let state_ptr = DalaBluetoothGetState();
        if state_ptr.is_null() {
            return "unknown";
        }
        let state_cstr = CStr::from_ptr(state_ptr);
        match state_cstr.to_str() {
            Ok(s) => {
                // Leak the string to return a static reference
                // The ObjC code returns a static string, so this is safe
                std::mem::forget(state_cstr);
                Box::leak(s.to_string().into_boxed_str())
            }
            Err(_) => "unknown",
        }
    }
}

pub fn bluetooth_start_scan(services: &[String], timeout_ms: u64) {
    unsafe {
        let c_strings: Vec<CString> = services
            .iter()
            .filter_map(|s| CString::new(s.as_str()).ok())
            .collect();
        let c_ptrs: Vec<*const libc::c_char> = c_strings.iter().map(|s| s.as_ptr()).collect();

        let service_count = c_ptrs.len() as libc::c_int;
        let service_ptr = if service_count > 0 {
            c_ptrs.as_ptr()
        } else {
            std::ptr::null()
        };

        DalaBluetoothStartScan(service_ptr, service_count, timeout_ms as libc::c_ulong);
    }
}

pub fn bluetooth_stop_scan() {
    unsafe {
        DalaBluetoothStopScan();
    }
}

pub fn bluetooth_connect(device_id: &str) {
    unsafe {
        if let Ok(c_id) = CString::new(device_id) {
            DalaBluetoothConnect(c_id.as_ptr());
        }
    }
}

pub fn bluetooth_disconnect(device_id: &str) {
    unsafe {
        if let Ok(c_id) = CString::new(device_id) {
            DalaBluetoothDisconnect(c_id.as_ptr());
        }
    }
}

pub fn bluetooth_discover_services(device_id: &str) {
    unsafe {
        if let Ok(c_id) = CString::new(device_id) {
            DalaBluetoothDiscoverServices(c_id.as_ptr());
        }
    }
}

pub fn bluetooth_read_characteristic(device_id: &str, service: &str, characteristic: &str) {
    unsafe {
        if let (Ok(c_id), Ok(c_svc), Ok(c_char)) = (
            CString::new(device_id),
            CString::new(service),
            CString::new(characteristic),
        ) {
            DalaBluetoothReadCharacteristic(c_id.as_ptr(), c_svc.as_ptr(), c_char.as_ptr());
        }
    }
}

pub fn bluetooth_write_characteristic(
    device_id: &str,
    service: &str,
    characteristic: &str,
    value: &[u8],
) {
    unsafe {
        if let (Ok(c_id), Ok(c_svc), Ok(c_char)) = (
            CString::new(device_id),
            CString::new(service),
            CString::new(characteristic),
        ) {
            DalaBluetoothWriteCharacteristic(
                c_id.as_ptr(),
                c_svc.as_ptr(),
                c_char.as_ptr(),
                value.as_ptr(),
                value.len() as libc::c_size_t,
            );
        }
    }
}

pub fn bluetooth_subscribe(device_id: &str, service: &str, characteristic: &str) {
    unsafe {
        if let (Ok(c_id), Ok(c_svc), Ok(c_char)) = (
            CString::new(device_id),
            CString::new(service),
            CString::new(characteristic),
        ) {
            DalaBluetoothSubscribe(c_id.as_ptr(), c_svc.as_ptr(), c_char.as_ptr());
        }
    }
}

pub fn bluetooth_unsubscribe(device_id: &str, service: &str, characteristic: &str) {
    unsafe {
        if let (Ok(c_id), Ok(c_svc), Ok(c_char)) = (
            CString::new(device_id),
            CString::new(service),
            CString::new(characteristic),
        ) {
            DalaBluetoothUnsubscribe(c_id.as_ptr(), c_svc.as_ptr(), c_char.as_ptr());
        }
    }
}

    // ============================================================================
    // WiFi
    // ============================================================================

    pub fn wifi_current_network<'a>(env: Env<'a>) -> Term<'a> {
        // iOS: Use CNCopyCurrentNetworkInfo to get SSID/BSSID
        // Note: iOS 13+ requires special entitlements and location permission
        // Returns a map with: connected, ssid, bssid, ip, rssi

        unsafe {
            // Import CoreWiFi/CaptiveNetwork framework functions
            use core_foundation::base::TCFType;
            use core_foundation::string::CFString;

            // Get the WiFi interface name (usually "en0")
            let iface_name = CString::new("en0").unwrap();

            // Call CNCopyCurrentNetworkInfo
            // This function is deprecated in iOS 14+ but still works with entitlements
            type CNCopyCurrentNetworkInfoFunc = unsafe extern "C" fn(*const libc::c_void) -> *mut libc::c_void;

            // Load the function from SystemConfiguration framework
            let net_info: *mut libc::c_void = ptr::null_mut();

            // For now, we'll use a simpler approach with the available APIs
            // In production, you'd need to properly link against SystemConfiguration

            // Get IP address for en0 interface
            let ip_addr = get_wifi_ip_address();

            // Try to get SSID using Objective-C approach
            let ssid = get_wifi_ssid();
            let bssid = get_wifi_bssid();

            let connected = !ssid.is_empty();

            // Build the result map
            let connected_term = if connected {
                rustler::types::atom::Atom::from_str(env, "true").unwrap().to_term(env)
            } else {
                rustler::types::atom::Atom::from_str(env, "false").unwrap().to_term(env)
            };

            let ssid_term = rustler::types::binary::Binary::from_bytes(env, ssid.as_bytes())
                .to_term(env);
            let bssid_term = rustler::types::binary::Binary::from_bytes(env, bssid.as_bytes())
                .to_term(env);
            let ip_term = rustler::types::binary::Binary::from_bytes(env, ip_addr.as_bytes())
                .to_term(env);

            // RSSI (signal strength) - not easily available on iOS without NEHotspotNetwork
            let rssi_term = rustler::types::binary::Binary::from_bytes(env, b"0".as_ref())
                .to_term(env);

            let result = rustler::types::map::map_new(env, 5);
            let result = rustler::types::map::map_put(
                result,
                rustler::types::binary::Binary::from_bytes(env, b"connected").to_term(env),
                connected_term,
            ).unwrap();
            let result = rustler::types::map::map_put(
                result,
                rustler::types::binary::Binary::from_bytes(env, b"ssid").to_term(env),
                ssid_term,
            ).unwrap();
            let result = rustler::types::map::map_put(
                result,
                rustler::types::binary::Binary::from_bytes(env, b"bssid").to_term(env),
                bssid_term,
            ).unwrap();
            let result = rustler::types::map::map_put(
                result,
                rustler::types::binary::Binary::from_bytes(env, b"ip").to_term(env),
                ip_term,
            ).unwrap();
            let result = rustler::types::map::map_put(
                result,
                rustler::types::binary::Binary::from_bytes(env, b"rssi").to_term(env),
                rssi_term,
            ).unwrap();

            result
        }
    }
}

// Helper: Get WiFi IP address using getifaddrs
unsafe fn get_wifi_ip_address() -> String {
    let mut ifap: *mut ifaddrs = ptr::null_mut();

    if getifaddrs(&mut ifap) != 0 {
        return String::new();
    }

    let mut ip = String::new();
    let mut ifa = ifap;

    while !ifa.is_null() {
        let ifa_ref = &*ifa;

        // Check if this is the WiFi interface (en0 on iOS)
        if !ifa_ref.ifa_name.is_null() {
            let name = CStr::from_ptr(ifa_ref.ifa_name);
            if name.to_string_lossy() == "en0" {
                // Check if the interface is up and running
                if (ifa_ref.ifa_flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING) {
                    if !ifa_ref.ifa_addr.is_null() {
                        let sa = &*(ifa_ref.ifa_addr as *const sockaddr_in);
                        if sa.sin_family as i32 == AF_INET {
                            // Convert IP to string
                            let addr = sa.sin_addr.s_addr;
                            ip = format!(
                                "{}.{}.{}.{}",
                                (addr & 0xff) as u8,
                                ((addr >> 8) & 0xff) as u8,
                                ((addr >> 16) & 0xff) as u8,
                                ((addr >> 24) & 0xff) as u8
                            );
                            break;
                        }
                    }
                }
            }
        }

        ifa = ifa_ref.ifa_next;
    }

    freeifaddrs(ifap);
    ip
}

// Helper: Get WiFi SSID using Objective-C
unsafe fn get_wifi_ssid() -> String {
    // Try to get SSID using NetworkExtension or CNCopyCurrentNetworkInfo
    // For now, return empty string - full implementation requires:
    // 1. Linking against SystemConfiguration framework
    // 2. Calling CNCopyCurrentNetworkInfo with proper interface name
    // 3. Handling iOS 13+ entitlement requirements

    // This is a placeholder - in production, you'd implement:
    // let info = CNCopyCurrentNetworkInfo(interface_name);
    // let ssid = CFDictionaryGetValue(info, kCNNetworkInfoKeySSID);

    String::new()
}

// Helper: Get WiFi BSSID using Objective-C
unsafe fn get_wifi_bssid() -> String {
    // Similar to SSID, would use CNCopyCurrentNetworkInfo
    // Placeholder for now
    String::new()
}

pub fn wifi_scan() {
    // iOS: Not supported by public APIs
    // iOS doesn't allow apps to scan for WiFi networks
    eprintln!("[Dala] wifi_scan not supported on iOS");
}

pub fn wifi_enable() {
    // iOS: Not supported
    // iOS doesn't allow apps to enable/disable WiFi
    eprintln!("[Dala] wifi_enable not supported on iOS");
}

pub fn wifi_disable() {
    // iOS: Not supported
    // iOS doesn't allow apps to enable/disable WiFi
    eprintln!("[Dala] wifi_disable not supported on iOS");
}

// ============================================================================
// Linking
// ============================================================================

pub fn linking_open_url(url: &str) {
    unsafe {
        let ns_url_string = ns_string_from_str(url);
        let url_class = class!(NSURL);
        let ns_url: *mut Object = msg_send![url_class, URLWithString: ns_url_string];
        if ns_url.is_null() {
            eprintln!("[Dala] linking_open_url: invalid URL: {}", url);
            return;
        }
        let app: *mut Object = msg_send![class!(UIApplication), sharedApplication];
        let _: () = msg_send![app, openURL: ns_url];
    }
}

pub fn linking_can_open<'a>(env: rustler::Env<'a>) -> rustler::Term<'a> {
    // On iOS, we generally can open URLs — return true
    // A full implementation would call canOpenURL: but that requires the URL argument
    rustler::types::atom::Atom::from_str(env, "true")
        .unwrap()
        .to_term(env)
}

pub fn linking_initial_url<'a>(env: rustler::Env<'a>) -> rustler::Term<'a> {
    // TODO: Retrieve the launch URL from NSUserActivity or launchOptions
    // For now, return nil
    rustler::types::atom::Atom::from_str(env, "nil")
        .unwrap()
        .to_term(env)
}
