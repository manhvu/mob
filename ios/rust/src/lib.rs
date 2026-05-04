// lib.rs - Main library for iOS Rust port.

#[no_mangle]
pub static mut driver_tab: [i32; 3] = [1, 2, 0];

#[no_mangle]
pub extern "C" fn erts_init_static_drivers() {
    // No-op
}

#[no_mangle]
pub extern "C" fn mob_start_beam(_app_module: *const i8) {
    println!("mob_start_beam called");
}

#[no_mangle]
pub extern "C" fn mob_set_startup_phase(_phase: *const i8) {
    println!("mob_set_startup_phase called");
}

#[no_mangle]
pub extern "C" fn mob_set_startup_error(_error: *const i8) {
    println!("mob_set_startup_error called");
}

#[no_mangle]
pub static mut g_jvm: *mut std::ffi::c_void = std::ptr::null_mut();
