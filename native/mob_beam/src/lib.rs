// lib.rs - Mob BEAM launcher and JNI bridge initialization in Rust
// Converted from mob_beam.c

mod driver_tab_android;
mod driver_tab_ios;
mod header;

use jni::objects::{JClass, JObject, JString, JValue};
use jni::sys::{JNIEnv as JNISysEnv, JavaVM};
use jni::{JNIEnv, NativeMethod};
use lazy_static::lazy_static;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::Mutex;

// ERTS version
const ERTS_VSN: &str = "erts-16.3";

// Global state
lazy_static! {
    static ref G_JVM: Mutex<Option<*mut JavaVM>> = Mutex::new(None);
    static ref G_ACTIVITY: Mutex<Option<JObject<'static>>> = Mutex::new(None);
    static ref S_NATIVE_LIB_DIR: Mutex<String> = Mutex::new(String::new());
    static ref S_FILES_DIR: Mutex<String> = Mutex::new(String::new());
}

// External function from mob_nif crate
extern "C" {
    pub fn mob_nif_nif_init() -> *mut c_void;
}

// ── JNI utility functions ─────────────────────────────────────────────────

unsafe fn get_env_from_jvm(jvm: *mut JavaVM) -> Option<*mut JNIEnv> {
    let mut env: *mut JNIEnv = ptr::null_mut();
    let jvm = &*jvm;
    let get_env = (*jvm).GetEnv.unwrap();
    match get_env(jvm, &mut env as *mut *mut JNIEnv, jni::sys::JNI_VERSION_1_6) {
        jni::sys::JNI_OK => Some(env),
        _ => {
            let attach = (*jvm).AttachCurrentThread.unwrap();
            match attach(jvm, &mut env as *mut *mut JNIEnv, ptr::null_mut()) {
                jni::sys::JNI_OK => Some(env),
                _ => None,
            }
        }
    }
}

// ── mob_ui_cache_class ──────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn Java_com_example_mob_MobBridge_nativeUiCacheClass(
    env: JNIEnv,
    _class: JClass,
    bridge_class: JString,
) {
    // This would call _mob_ui_cache_class_impl from mob_nif
    // For now, stub implementation
    let _ = env;
    let _ = bridge_class;
}

// ── mob_init_bridge ─────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn Java_com_example_mob_MobBridge_nativeInitBridge(
    env: JNIEnv,
    _class: JClass,
    activity: JObject,
) {
    // Cache the activity as global ref
    let jvm = unsafe {
        let mut vm: *mut JavaVM = ptr::null_mut();
        if env.get_java_vm().is_ok() {
            // Store JVM pointer
            let vm_ptr = Box::into_raw(Box::new(env.get_java_vm().unwrap()));
            // This is simplified - in reality need proper JVM pointer handling
        }
    };

    // Get nativeLibraryDir
    let ctx_cls = env.find_class("android/content/Context").unwrap();
    let get_app_info = env
        .get_method_id(
            &ctx_cls,
            "getApplicationInfo",
            "()Landroid/content/pm/ApplicationInfo;",
        )
        .unwrap();
    let app_info = env
        .call_method(
            &activity,
            "getApplicationInfo",
            "()Landroid/content/pm/ApplicationInfo;",
            &[],
        )
        .unwrap()
        .l()
        .unwrap();

    let app_info_cls = env
        .find_class("android/content/pm/ApplicationInfo")
        .unwrap();
    let fid = env
        .get_field_id(&app_info_cls, "nativeLibraryDir", "Ljava/lang/String;")
        .unwrap();
    let jdir = env
        .get_field(&app_info, "nativeLibraryDir", "Ljava/lang/String;")
        .unwrap()
        .l()
        .unwrap();
    let dir = env.get_string(jdir.into()).unwrap();
    let native_lib_dir = dir.to_string_lossy().to_string();

    {
        let mut s = S_NATIVE_LIB_DIR.lock().unwrap();
        *s = native_lib_dir.clone();
    }

    android_log!("mob_init_bridge: native lib dir = {}", native_lib_dir);

    // Get filesDir
    let get_files_dir = env
        .get_method_id(&ctx_cls, "getFilesDir", "()Ljava/io/File;")
        .unwrap();
    let files_dir_obj = env
        .call_method(&activity, "getFilesDir", "()Ljava/io/File;", &[])
        .unwrap()
        .l()
        .unwrap();

    let file_cls = env.find_class("java/io/File").unwrap();
    let get_path = env
        .get_method_id(&file_cls, "getPath", "()Ljava/lang/String;")
        .unwrap();
    let jfiles_path = env
        .call_method(&files_dir_obj, "getPath", "()Ljava/lang/String;", &[])
        .unwrap()
        .l()
        .unwrap();
    let files_path = env.get_string(jfiles_path.into()).unwrap();
    let files_dir = files_path.to_string_lossy().to_string();

    {
        let mut s = S_FILES_DIR.lock().unwrap();
        *s = files_dir.clone();
    }

    android_log!("mob_init_bridge: files dir = {}", files_dir);
}

// ── mob_start_beam ──────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn Java_com_example_mob_MobBridge_nativeStartBeam(
    env: JNIEnv,
    _class: JClass,
    app_module: JString,
) {
    let module = env.get_string(app_module.into()).unwrap();
    let app_module_str = module.to_string_lossy().to_string();

    start_beam(&app_module_str);
}

fn start_beam(app_module: &str) {
    // Check NO_BEAM flag
    #[cfg(feature = "no_beam")]
    {
        android_log!("mob_start_beam: NO_BEAM defined, skipping BEAM launch (battery baseline)");
        return;
    }

    set_startup_phase("Setting up BEAM environment…");

    let files_dir = S_FILES_DIR.lock().unwrap().clone();
    let native_lib_dir = S_NATIVE_LIB_DIR.lock().unwrap().clone();

    // Build paths
    let otp_root = format!("{}/otp", files_dir);
    let bindir = format!("{}/{}/bin", otp_root, ERTS_VSN);
    let beams_dir = format!("{}/{}", otp_root, app_module);
    let elixir_dir = format!("{}/lib/elixir/ebin", otp_root);
    let logger_dir = format!("{}/lib/logger/ebin", otp_root);
    let eex_dir = format!("{}/lib/eex/ebin", otp_root);
    let crash_dump = format!("{}/erl_crash.dump", files_dir);

    // Set environment variables
    std::env::set_var("BINDIR", &bindir);
    std::env::set_var("ROOTDIR", &otp_root);
    std::env::set_var("PROGNAME", "erl");
    std::env::set_var("EMU", "beam");
    std::env::set_var("HOME", &files_dir);
    std::env::set_var("MOB_DATA_DIR", &files_dir);
    std::env::set_var("MOB_BEAMS_DIR", &beams_dir);
    std::env::set_var("ERL_CRASH_DUMP", &crash_dump);
    std::env::set_var("ERL_CRASH_DUMP_SECONDS", "30");

    let eval_expr = format!("{}:start().", app_module);

    // BEAM tuning flags
    let default_flags: &[&str] = if cfg!(feature = "beam_untuned") {
        &[]
    } else if cfg!(feature = "beam_sbwt_only") {
        &["-sbwt", "none", "-sbwtdcpu", "none", "-sbwtdio", "none"]
    } else {
        // Default: BEAM_FULL_NERVES
        &[
            "-S",
            "1:1",
            "-SDcpu",
            "1:1",
            "-SDio",
            "1",
            "-A",
            "1",
            "-sbwt",
            "none",
            "-sbwtdcpu",
            "none",
            "-sbwtdio",
            "none",
        ]
    };

    // Runtime override: read flags from beams_dir/mob_beam_flags
    let mut runtime_flags: Vec<String> = Vec::new();
    let flags_path = format!("{}/mob_beam_flags", beams_dir);
    if let Ok(contents) = std::fs::read_to_string(&flags_path) {
        runtime_flags = contents.split_whitespace().map(|s| s.to_string()).collect();
        android_log!(
            "mob_start_beam: loaded {} runtime flags from {}",
            runtime_flags.len(),
            flags_path
        );
    }

    let selected_flags: &[&str] = if !runtime_flags.is_empty() {
        // This is a simplification - would need proper lifetime handling
        &[]
    } else {
        default_flags
    };

    let boot_path = format!("{}/releases/29/start_clean", otp_root);

    // Build args
    let mut args: Vec<&str> = vec!["beam"];
    args.extend_from_slice(selected_flags);
    args.push("--");
    args.push("-root");
    args.push(&otp_root);
    args.push("-bindir");
    args.push(&bindir);
    args.push("-progname");
    args.push("erl");
    args.push("--");
    args.push("-noshell");
    args.push("-noinput");
    args.push("-boot");
    args.push(&boot_path);
    args.push("-pa");
    args.push(&elixir_dir);
    args.push("-pa");
    args.push(&logger_dir);
    args.push("-pa");
    args.push(&eex_dir);
    args.push("-pa");
    args.push(&beams_dir);
    args.push("-eval");
    args.push(&eval_expr);

    // Cold-start race condition fix: wait for window focus
    wait_for_window_focus();

    set_startup_phase("Starting BEAM…");
    android_log!(
        "mob_start_beam: starting BEAM with module={}, argc={}",
        app_module,
        args.len(),
    );

    // Symlink ERTS executables
    if !native_lib_dir.is_empty() {
        let exes = vec![
            ("erl_child_setup", "liberl_child_setup.so"),
            ("inet_gethost", "libinet_gethost.so"),
            ("epmd", "libepmd.so"),
        ];
        for (exe, lib) in exes {
            let bin_path = format!("{}/{}/bin/{}", otp_root, ERTS_VSN, exe);
            let lib_path = format!("{}/{}", native_lib_dir, lib);
            let _ = std::fs::remove_file(&bin_path);
            if std::os::unix::fs::symlink(&lib_path, &bin_path).is_ok() {
                android_log!("mob_start_beam: symlink {} -> {}", exe, lib_path);
            }
        }
    }

    // Call erl_start (external C function from ERTS)
    // This would need proper FFI declaration
    // erl_start(args.len() as c_int, args.as_ptr() as *mut *mut c_char);
}

// ── Cold-start race condition fix ───────────────────────────────────────

fn wait_for_window_focus() {
    let jvm_guard = G_JVM.lock().unwrap();
    if let Some(jvm) = *jvm_guard {
        // Would need proper implementation with JNI calls
        // Poll Activity.hasWindowFocus() every 50ms for up to 3 seconds
    }
}

// ── Helper: Android logging ─────────────────────────────────────

fn android_log(fmt: &str, args: &str) {
    #[cfg(target_os = "android")]
    {
        android_logger::init_once(
            android_logger::Config::default()
                .with_min_level(log::Level::Info)
                .with_tag("MobBeam"),
        );
        log::info!("{}{}", fmt, args);
    }
    #[cfg(not(target_os = "android"))]
    {
        println!("[MobBeam] {}{}", fmt, args);
    }
}

// Overload for multiple arguments using format!
#[allow(unused_macros)]
macro_rules! android_log {
    ($fmt:expr) => {
        android_log($fmt, "");
    };
    ($fmt:expr, $($arg:tt)*) => {
        android_log(&format!($fmt, $($arg)*), "");
    };
}

fn set_startup_phase(_phase: &str) {
    // Would call MobBridge.setStartupPhase via JNI
}

// ── Event sender stubs (to be implemented) ───────────────────────────────

#[no_mangle]
pub extern "C" fn mob_send_tap(_handle: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn mob_send_change_str(_handle: c_int, _utf8: *const c_char) {
    // Stub
}

#[no_mangle]
pub extern "C" fn mob_send_change_bool(_handle: c_int, _bool_val: c_int) {
    // Stub
}

#[no_mangle]
pub extern "C" fn mob_send_change_float(_handle: c_int, _value: f64) {
    // Stub
}

// Re-export header functions
pub use header::*;

// ... (other event senders would follow the same pattern)
