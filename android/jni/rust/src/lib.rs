// lib.rs - Simple test library for Android

#![allow(dead_code)]

#[no_mangle]
pub static mut driver_tab: [i32; 3] = [1, 2, 0];

#[no_mangle]
pub extern "C" fn erts_init_static_drivers() {
    // No-op
}

#[no_mangle]
pub extern "C" fn dala_start_beam(_app_module: *const i8) {
    println!("dala_start_beam called");
}

#[no_mangle]
pub extern "C" fn dala_set_startup_phase(_phase: *const i8) {
    println!("dala_set_startup_phase called");
}

#[no_mangle]
pub extern "C" fn dala_set_startup_error(_error: *const i8) {
    println!("dala_set_startup_error called");
}

// JNI_OnLoad is called when the native library is loaded
// This sets the g_jvm pointer in the dala_nif crate
#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn JNI_OnLoad(
    vm: *mut jni::sys::JavaVM,
    _reserved: *mut std::ffi::c_void,
) -> jni::sys::jint {
    // Set the g_jvm pointer in dala_nif crate
    // We need to use the full crate path
    unsafe {
        // The g_jvm is defined in dala_nif::g_jvm
        // Since we're in a separate crate, we need to use FFI or make it accessible
        // For now, we'll store it locally and have dala_nif read from here
        G_JVM = vm as *mut std::ffi::c_void;
    }
    jni::sys::JNI_VERSION_1_6
}

// Store JavaVM pointer here - dala_nif will read from this
#[no_mangle]
pub static mut G_JVM: *mut std::ffi::c_void = std::ptr::null_mut();
