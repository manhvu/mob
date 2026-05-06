// android.rs - Android-specific NIF implementations using JNI

use jni::objects::{JClass, JString, JValue};
use jni::JNIEnv;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

// Global storage for BluetoothGatt objects (device_id -> BluetoothGatt reference)
// This is needed because BLE operations require the BluetoothGatt object from the connection
lazy_static::lazy_static! {
    static ref GATT_CONNECTIONS: Arc<Mutex<HashMap<String, jni::objects::GlobalRef>>> =
        Arc::new(Mutex::new(HashMap::new()));
}

// Helper: get the DalaBridge class
unsafe fn get_bridge_class<'a>(env: &mut JNIEnv<'a>) -> Option<JClass<'a>> {
    match env.find_class("com/example/dala/DalaBridge") {
        Ok(c) => Some(c),
        Err(e) => {
            eprintln!("[Dala] Failed to find DalaBridge class: {:?}", e);
            None
        }
    }
}

// Helper: get JNIEnv from JavaVM (for functions that don't receive it directly)
unsafe fn get_jni_env() -> Option<JNIEnv<'static>> {
    // G_JVM is defined in dala-beam-android crate (android/jni/rust/src/lib.rs)
    // It's set during JNI_OnLoad
    extern "C" {
        #[link_name = "G_JVM"]
        static G_JVM: *mut std::ffi::c_void;
    }

    if G_JVM.is_null() {
        eprintln!("[Dala] G_JVM is null");
        return None;
    }
    let jvm = &*(G_JVM as *mut jni::JavaVM);
    match jvm.attach_current_thread() {
        Ok(env) => Some(env),
        Err(e) => {
            eprintln!("[Dala] Failed to attach thread: {:?}", e);
            None
        }
    }
}

// Helper: convert Rust string to Java string
unsafe fn to_jstring<'a>(env: &mut JNIEnv<'a>, s: &str) -> Option<JString<'a>> {
    match env.new_string(s) {
        Ok(jstr) => Some(jstr),
        Err(e) => {
            eprintln!("[Dala] Failed to create jstring: {:?}", e);
            None
        }
    }
}

// Helper: call a void method on DalaBridge
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
    eprintln!("[Dala] {}", msg);
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
    eprintln!("[Dala] exit_app called (stub)");
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
    // 1. Get WebView instance from DalaBridge
    // 2. Call drawing cache or PixelCopy (API 26+)
    // 3. Compress to PNG and return data
    eprintln!("[Dala] webview_screenshot not yet implemented");
    false
}

// ============================================================================
// Bluetooth (BLE)
// ============================================================================
// Note: These functions need JNIEnv to call Android APIs.
// The actual implementation delegates to DalaBridge Java class which has
// access to the Android Bluetooth APIs.

pub fn bluetooth_state<'a>() -> &'a str {
    // Android: BluetoothAdapter state
    // States: STATE_OFF=10, STATE_TURNING_ON=11, STATE_ON=12, STATE_TURNING_OFF=13
    // This is a stub - in practice, we'd call through JNI to BluetoothAdapter.getState()
    // For now, return "unknown" since we can't access JNIEnv from this function signature
    "unknown"
}

// Internal helper that takes JNIEnv - called from NIFs that have env access
pub fn bluetooth_state_with_env(env: &mut JNIEnv) -> String {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothGetState";
        let sig = "()Ljava/lang/String;";
        if let Ok(val) = env.call_static_method(class, method, sig, &[]) {
            if let Ok(jstr) = val.l() {
                if let Ok(state) = env.get_string(&jstr.into()) {
                    return state.to_string_lossy().to_string();
                }
            }
        }
    }
    "unknown".to_string()
}

pub fn bluetooth_start_scan(services: &[String], timeout_ms: u64) {
    // Android: BluetoothLeScanner startScan
    // This function doesn't have JNIEnv - we need to refactor to pass it
    // For now, log that this needs JNIEnv
    eprintln!(
        "[Dala] bluetooth_start_scan needs JNIEnv - use bluetooth_start_scan_with_env instead"
    );
}

// Internal helper with JNIEnv access
pub fn bluetooth_start_scan_with_env(env: &mut JNIEnv, services: &[String], timeout_ms: u64) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothStartScan";
        let sig = "(Ljava/util/List;J)V";

        // Create ArrayList of service UUIDs
        let array_list = if let Ok(list) = env.new_object("java/util/ArrayList", "()V", &[]) {
            list
        } else {
            eprintln!("[Dala] Failed to create ArrayList");
            return;
        };

        // Add services to list
        for service in services {
            if let Some(jstr) = to_jstring(env, service) {
                let _ = env.call_method(
                    &array_list,
                    "add",
                    "(Ljava/lang/Object;)Z",
                    &[JValue::Object(jstr.into())],
                );
            }
        }

        let args = [JValue::Object(array_list), JValue::Long(timeout_ms as i64)];

        match env.call_static_method(class, method, sig, &args) {
            Ok(_) => {}
            Err(e) => eprintln!("[Dala] bluetoothStartScan failed: {:?}", e),
        }
    }
}

pub fn bluetooth_stop_scan() {
    eprintln!("[Dala] bluetooth_stop_scan needs JNIEnv - use bluetooth_stop_scan_with_env instead");
}

pub fn bluetooth_stop_scan_with_env(env: &mut JNIEnv) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothStopScan";
        let sig = "()V";
        let _ = env.call_static_method(class, method, sig, &[]);
    }
}

pub fn bluetooth_connect(device_id: &str) {
    eprintln!("[Dala] bluetooth_connect needs JNIEnv - use bluetooth_connect_with_env instead");
}

pub fn bluetooth_connect_with_env(env: &mut JNIEnv, device_id: &str) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothConnect";
        let sig = "(Ljava/lang/String;)V";
        if let Some(jstr) = to_jstring(env, device_id) {
            let args = [JValue::Object(jstr.into())];
            match env.call_static_method(class, method, sig, &args) {
                Ok(_) => {}
                Err(e) => eprintln!("[Dala] bluetoothConnect failed: {:?}", e),
            }
        }
    }
}

pub fn bluetooth_disconnect(device_id: &str) {
    eprintln!(
        "[Dala] bluetooth_disconnect needs JNIEnv - use bluetooth_disconnect_with_env instead"
    );
}

pub fn bluetooth_disconnect_with_env(env: &mut JNIEnv, device_id: &str) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothDisconnect";
        let sig = "(Ljava/lang/String;)V";
        if let Some(jstr) = to_jstring(env, device_id) {
            let args = [JValue::Object(jstr.into())];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

pub fn bluetooth_discover_services(device_id: &str) {
    eprintln!("[Dala] bluetooth_discover_services needs JNIEnv - use bluetooth_discover_services_with_env instead");
}

pub fn bluetooth_discover_services_with_env(env: &mut JNIEnv, device_id: &str) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothDiscoverServices";
        let sig = "(Ljava/lang/String;)V";
        if let Some(jstr) = to_jstring(env, device_id) {
            let args = [JValue::Object(jstr.into())];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

pub fn bluetooth_read_characteristic(device_id: &str, service: &str, characteristic: &str) {
    eprintln!("[Dala] bluetooth_read_characteristic needs JNIEnv");
}

pub fn bluetooth_read_characteristic_with_env(
    env: &mut JNIEnv,
    device_id: &str,
    service: &str,
    characteristic: &str,
) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothReadCharacteristic";
        let sig = "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V";
        if let (Some(dev), Some(srv), Some(chr)) = (
            to_jstring(env, device_id),
            to_jstring(env, service),
            to_jstring(env, characteristic),
        ) {
            let args = [
                JValue::Object(dev.into()),
                JValue::Object(srv.into()),
                JValue::Object(chr.into()),
            ];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

pub fn bluetooth_write_characteristic(
    device_id: &str,
    service: &str,
    characteristic: &str,
    value: &[u8],
) {
    eprintln!("[Dala] bluetooth_write_characteristic needs JNIEnv");
}

pub fn bluetooth_write_characteristic_with_env(
    env: &mut JNIEnv,
    device_id: &str,
    service: &str,
    characteristic: &str,
    value: &[u8],
) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothWriteCharacteristic";
        let sig = "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;[B)V";
        if let (Some(dev), Some(srv), Some(chr)) = (
            to_jstring(env, device_id),
            to_jstring(env, service),
            to_jstring(env, characteristic),
        ) {
            // Create byte array
            let byte_array = match env.byte_array_from_slice(value) {
                Ok(arr) => arr,
                Err(e) => {
                    eprintln!("[Dala] Failed to create byte array: {:?}", e);
                    return;
                }
            };
            let args = [
                JValue::Object(dev.into()),
                JValue::Object(srv.into()),
                JValue::Object(chr.into()),
                JValue::Object(byte_array.into()),
            ];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

pub fn bluetooth_subscribe(device_id: &str, service: &str, characteristic: &str) {
    eprintln!("[Dala] bluetooth_subscribe needs JNIEnv");
}

pub fn bluetooth_subscribe_with_env(
    env: &mut JNIEnv,
    device_id: &str,
    service: &str,
    characteristic: &str,
) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothSubscribe";
        let sig = "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V";
        if let (Some(dev), Some(srv), Some(chr)) = (
            to_jstring(env, device_id),
            to_jstring(env, service),
            to_jstring(env, characteristic),
        ) {
            let args = [
                JValue::Object(dev.into()),
                JValue::Object(srv.into()),
                JValue::Object(chr.into()),
            ];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

pub fn bluetooth_unsubscribe(device_id: &str, service: &str, characteristic: &str) {
    eprintln!("[Dala] bluetooth_unsubscribe needs JNIEnv");
}

pub fn bluetooth_unsubscribe_with_env(
    env: &mut JNIEnv,
    device_id: &str,
    service: &str,
    characteristic: &str,
) {
    if let Some(class) = get_bridge_class(env) {
        let method = "bluetoothUnsubscribe";
        let sig = "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V";
        if let (Some(dev), Some(srv), Some(chr)) = (
            to_jstring(env, device_id),
            to_jstring(env, service),
            to_jstring(env, characteristic),
        ) {
            let args = [
                JValue::Object(dev.into()),
                JValue::Object(srv.into()),
                JValue::Object(chr.into()),
            ];
            let _ = env.call_static_method(class, method, sig, &args);
        }
    }
}

// ============================================================================
// WiFi
// ============================================================================

pub fn wifi_current_network<'a>(env: Env<'a>) -> Term<'a> {
    // Android: WifiManager getConnectionInfo
    // Returns a map with: connected, ssid, bssid, ip, rssi

    unsafe {
        if let Some(mut jni_env) = get_jni_env() {
            // Call DalaBridge.getWifiInfo() which returns a String with JSON
            if let Some(class) = get_bridge_class(&mut jni_env) {
                let method = "getWifiInfo";
                let sig = "()Ljava/lang/String;";
                if let Ok(val) = jni_env.call_static_method(class, method, sig, &[]) {
                    if let Ok(jstring) = val.l() {
                        if let Ok(info_str) = jni_env.get_string(&JString::from(jstring)) {
                            let info: String = info_str.into();
                            // Parse the JSON string and convert to Erlang map
                            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&info) {
                                let connected = json["connected"].as_bool().unwrap_or(false);
                                let ssid = json["ssid"].as_str().unwrap_or("");
                                let bssid = json["bssid"].as_str().unwrap_or("");
                                let ip = json["ip"].as_str().unwrap_or("");
                                let rssi = json["rssi"].as_i64().unwrap_or(0) as i32;

                                // Create an Erlang map
                                let mut map = rustler::types::map::map_new(env);

                                let connected_atom = if connected {
                                    atom(env, "true")
                                } else {
                                    atom(env, "false")
                                };
                                map = rustler::types::map::map_put(
                                    env,
                                    map,
                                    atom(env, "connected"),
                                    connected_atom,
                                )
                                .unwrap();
                                map = rustler::types::map::map_put(
                                    env,
                                    map,
                                    atom(env, "ssid"),
                                    rustler::types::binary::Binary::from_slice(
                                        env,
                                        ssid.as_bytes(),
                                    )
                                    .unwrap()
                                    .to_term(env),
                                )
                                .unwrap();
                                map = rustler::types::map::map_put(
                                    env,
                                    map,
                                    atom(env, "bssid"),
                                    rustler::types::binary::Binary::from_slice(
                                        env,
                                        bssid.as_bytes(),
                                    )
                                    .unwrap()
                                    .to_term(env),
                                )
                                .unwrap();
                                map = rustler::types::map::map_put(
                                    env,
                                    map,
                                    atom(env, "ip"),
                                    rustler::types::binary::Binary::from_slice(env, ip.as_bytes())
                                        .unwrap()
                                        .to_term(env),
                                )
                                .unwrap();
                                map = rustler::types::map::map_put(
                                    env,
                                    map,
                                    atom(env, "rssi"),
                                    rustler::types::Binary::from_slice(env, &rssi.to_be_bytes())
                                        .unwrap()
                                        .to_term(env),
                                )
                                .unwrap();

                                return map;
                            }
                        }
                    }
                }
            }
        }
    }

    // Return unknown if we couldn't get the info
    atom(env, "unknown")
}

pub fn wifi_scan() {
    // Android: WifiManager startScan
    // Note: startScan() is deprecated in API 28+ but still works
    // Results come asynchronously via BroadcastReceiver
    // Requires ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION permission

    unsafe {
        if let Some(mut jni_env) = get_jni_env() {
            if let Some(class) = get_bridge_class(&mut jni_env) {
                let method = "startWifiScan";
                let sig = "()V";
                let _ = jni_env.call_static_method(class, method, sig, &[]);
            }
        } else {
            eprintln!("[Dala] wifi_scan: could not get JNIEnv");
        }
    }
}

pub fn wifi_enable() {
    // Android: WifiManager setWifiEnabled(true)
    // Requires CHANGE_WIFI_STATE permission

    unsafe {
        if let Some(mut jni_env) = get_jni_env() {
            if let Some(class) = get_bridge_class(&mut jni_env) {
                let method = "setWifiEnabled";
                let sig = "(Z)V";
                let args = [JValue::Bool(1)]; // true = enable
                let _ = jni_env.call_static_method(class, method, sig, &args);
            }
        } else {
            eprintln!("[Dala] wifi_enable: could not get JNIEnv");
        }
    }
}

pub fn wifi_disable() {
    // Android: WifiManager setWifiEnabled(false)
    // Requires CHANGE_WIFI_STATE permission

    unsafe {
        if let Some(mut jni_env) = get_jni_env() {
            if let Some(class) = get_bridge_class(&mut jni_env) {
                let method = "setWifiEnabled";
                let sig = "(Z)V";
                let args = [JValue::Bool(0)]; // false = disable
                let _ = jni_env.call_static_method(class, method, sig, &args);
            }
        } else {
            eprintln!("[Dala] wifi_disable: could not get JNIEnv");
        }
    }
}

// ============================================================================
// JNI Native Methods - Callbacks from Java DalaBridge
// ============================================================================
// These functions are called from Java via JNI when BLE events occur.
// They need to deliver messages back to Elixir.

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothDeviceFound(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    device_id: jni::objects::JString,
    name: jni::objects::JString,
    rssi: jni::sys::jint,
) {
    let device_id_str = match env.get_string(&device_id) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let name_str = match env.get_string(&name) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };

    eprintln!(
        "[Dala] BLE device found: {} ({}), RSSI: {}",
        device_id_str, name_str, rssi
    );

    // TODO: Send to Elixir - need to call into BEAM
    // This requires using the dala_nif delivery mechanism
    // For now, we log the event
}

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothStateChanged(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    state: jni::objects::JString,
) {
    let state_str = match env.get_string(&state) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    eprintln!("[Dala] BLE state changed: {}", state_str);
}

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothConnected(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    device_id: jni::objects::JString,
) {
    let device_id_str = match env.get_string(&device_id) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    eprintln!("[Dala] BLE connected: {}", device_id_str);
}

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothDisconnected(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    device_id: jni::objects::JString,
) {
    let device_id_str = match env.get_string(&device_id) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    eprintln!("[Dala] BLE disconnected: {}", device_id_str);
}

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothServicesDiscovered(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    device_id: jni::objects::JString,
    services_json: jni::objects::JString,
) {
    let device_id_str = match env.get_string(&device_id) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let services_str = match env.get_string(&services_json) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    eprintln!(
        "[Dala] BLE services discovered for {}: {}",
        device_id_str, services_str
    );
}

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothCharacteristicRead(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    device_id: jni::objects::JString,
    service: jni::objects::JString,
    characteristic: jni::objects::JString,
    value: jni::objects::JByteArray,
) {
    let device_id_str = match env.get_string(&device_id) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let service_str = match env.get_string(&service) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let char_str = match env.get_string(&characteristic) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let value_bytes = match env.convert_byte_array(value) {
        Ok(v) => v,
        Err(_) => return,
    };
    eprintln!(
        "[Dala] BLE characteristic read: {}/{}/{} = {:?}",
        device_id_str, service_str, char_str, value_bytes
    );
}

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothCharacteristicWritten(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    device_id: jni::objects::JString,
    service: jni::objects::JString,
    characteristic: jni::objects::JString,
) {
    let device_id_str = match env.get_string(&device_id) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let service_str = match env.get_string(&service) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let char_str = match env.get_string(&characteristic) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    eprintln!(
        "[Dala] BLE characteristic written: {}/{}/{}",
        device_id_str, service_str, char_str
    );
}

#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeBluetoothNotificationReceived(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    device_id: jni::objects::JString,
    service: jni::objects::JString,
    characteristic: jni::objects::JString,
    value: jni::objects::JByteArray,
) {
    let device_id_str = match env.get_string(&device_id) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let service_str = match env.get_string(&service) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let char_str = match env.get_string(&characteristic) {
        Ok(s) => s.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let value_bytes = match env.convert_byte_array(value) {
        Ok(v) => v,
        Err(_) => return,
    };
    eprintln!(
        "[Dala] BLE notification: {}/{}/{} = {:?}",
        device_id_str, service_str, char_str, value_bytes
    );
}
