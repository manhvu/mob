// lib.rs - Dala BEAM launcher and JNI bridge initialization in Rust
// Converted from dala_beam.c

mod driver_tab_android;
mod driver_tab_ios;
mod header;

use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::{JNIEnv, JavaVM};
use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::{Mutex, OnceLock};

// ── Helper: Android logging ───────────────────────────────

fn android_log(fmt: &str, args: &str) {
    #[cfg(target_os = "android")]
    {
        android_logger::init_once(
            android_logger::Config::default()
                .with_min_level(log::Level::Info)
                .with_tag("DalaBeam"),
        );
        log::info!("{}{}", fmt, args);
    }
    #[cfg(not(target_os = "android"))]
    {
        println!("[DalaBeam] {}{}", fmt, args);
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

// ERTS version
const ERTS_VSN: &str = "erts-16.3";

// Global state - use GlobalRef for JNI objects that need to outlive the JNI call
static JVM: OnceLock<JavaVM> = OnceLock::new();
static ACTIVITY: Mutex<Option<GlobalRef>> = Mutex::new(None);
static NATIVE_LIB_DIR: Mutex<String> = Mutex::new(String::new());
static FILES_DIR: Mutex<String> = Mutex::new(String::new());

// External function from dala_nif crate
extern "C" {
    pub fn dala_nif_nif_init() -> *mut c_void;
}

// External BEAM entry point
extern "C" {
    /// ERTS entry point - starts the BEAM VM
    /// argc: number of arguments
    /// argv: array of C string pointers
    pub fn erl_start(argc: c_int, argv: *mut *mut c_char);
}

// ── JNI utility functions ──────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeUiCacheClass(
    env: JNIEnv,
    _class: JClass,
    bridge_class: JString,
) {
    // This would call _dala_ui_cache_class_impl from dala_nif
    // For now, stub implementation
    let _ = env;
    let _ = bridge_class;
}

// ── dala_init_bridge ─────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeInitBridge(
    mut env: JNIEnv,
    _class: JClass,
    activity: JObject,
) {
    // Cache the JavaVM
    if let Ok(jvm) = env.get_java_vm() {
        let _ = JVM.set(jvm);
    }

    // Cache the activity as a global reference for later use
    if let Ok(global_ref) = env.new_global_ref(&activity) {
        let mut guard = ACTIVITY.lock().unwrap();
        *guard = Some(global_ref);
    }

    // Get nativeLibraryDir via ApplicationInfo.nativeLibraryDir
    let app_info = match env.call_method(
        &activity,
        "getApplicationInfo",
        "()Landroid/content/pm/ApplicationInfo;",
        &[],
    ) {
        Ok(result) => match result.l() {
            Ok(obj) => obj,
            Err(_) => return,
        },
        Err(_) => return,
    };

    let jdir = match env.get_field(&app_info, "nativeLibraryDir", "Ljava/lang/String;") {
        Ok(result) => match result.l() {
            Ok(obj) => obj,
            Err(_) => return,
        },
        Err(_) => return,
    };
    let jdir_str = JString::from(jdir);
    let dir = match env.get_string(&jdir_str) {
        Ok(s) => s,
        Err(_) => return,
    };
    let native_lib_dir = dir.to_string_lossy().to_string();

    {
        let mut s = NATIVE_LIB_DIR.lock().unwrap();
        *s = native_lib_dir.clone();
    }

    android_log!("dala_init_bridge: native lib dir = {}", native_lib_dir);

    // Get filesDir via Context.getFilesDir()
    let files_dir_obj = match env.call_method(&activity, "getFilesDir", "()Ljava/io/File;", &[]) {
        Ok(result) => match result.l() {
            Ok(obj) => obj,
            Err(_) => return,
        },
        Err(_) => return,
    };

    let jfiles_path = match env.call_method(&files_dir_obj, "getPath", "()Ljava/lang/String;", &[])
    {
        Ok(result) => match result.l() {
            Ok(obj) => obj,
            Err(_) => return,
        },
        Err(_) => return,
    };
    let jfiles_str = JString::from(jfiles_path);
    let files_path = match env.get_string(&jfiles_str) {
        Ok(s) => s,
        Err(_) => return,
    };
    let files_dir = files_path.to_string_lossy().to_string();

    {
        let mut s = FILES_DIR.lock().unwrap();
        *s = files_dir.clone();
    }

    android_log!("dala_init_bridge: files dir = {}", files_dir);
}

// ── dala_start_beam ──────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeStartBeam(
    mut env: JNIEnv,
    _class: JClass,
    app_module: JString,
) {
    let module = match env.get_string(&app_module) {
        Ok(s) => s,
        Err(_) => return,
    };
    let app_module_str = module.to_string_lossy().to_string();

    start_beam(&app_module_str);
}

/// Set the startup phase message shown to the user during BEAM initialization.
/// This calls back to Java to update the UI.
fn set_startup_phase(phase: &str) {
    let jvm = match JVM.get() {
        Some(jvm) => jvm,
        None => return,
    };

    let mut env = match jvm.attach_current_thread() {
        Ok(env) => env,
        Err(_) => return,
    };

    // Call DalaBridge.setStartupPhase(String)
    let class = match env.find_class("com/example/dala/DalaBridge") {
        Ok(c) => c,
        Err(_) => return,
    };

    let phase_str = match env.new_string(phase) {
        Ok(s) => s,
        Err(_) => return,
    };

    let _ = env.call_static_method(
        class,
        "setStartupPhase",
        "(Ljava/lang/String;)V",
        &[JValue::Object(&phase_str)],
    );
}

/// Wait for the Activity to have window focus before starting BEAM.
/// This fixes a cold-start race condition where BEAM starts before the UI is ready.
fn wait_for_window_focus() {
    let jvm = match JVM.get() {
        Some(jvm) => jvm,
        None => return,
    };

    let mut env = match jvm.attach_current_thread() {
        Ok(env) => env,
        Err(_) => return,
    };

    let activity_guard = ACTIVITY.lock().unwrap();
    let activity = match activity_guard.as_ref() {
        Some(a) => a.as_obj(),
        None => return,
    };

    // Poll Activity.hasWindowFocus() with a timeout
    let max_attempts = 100; // 5 seconds max (100 * 50ms)
    for _ in 0..max_attempts {
        let has_focus = env
            .call_method(activity, "hasWindowFocus", "()Z", &[])
            .map(|r| r.z().unwrap_or(false))
            .unwrap_or(false);

        if has_focus {
            android_log!("wait_for_window_focus: activity has focus");
            return;
        }

        // Sleep 50ms before retrying
        std::thread::sleep(std::time::Duration::from_millis(50));
    }

    android_log!("wait_for_window_focus: timed out waiting for focus, proceeding anyway");
}

fn start_beam(app_module: &str) {
    // Check NO_BEAM flag
    #[cfg(feature = "no_beam")]
    {
        android_log!("dala_start_beam: NO_BEAM defined, skipping BEAM launch (battery baseline)");
        return;
    }

    set_startup_phase("Setting up BEAM environment…");

    // Get values from Mutex
    let files_dir = FILES_DIR.lock().unwrap().clone();
    let native_lib_dir = NATIVE_LIB_DIR.lock().unwrap().clone();

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
    std::env::set_var("DALA_DATA_DIR", &files_dir);
    std::env::set_var("DALA_BEAMS_DIR", &beams_dir);
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

    // Runtime override: read flags from beams_dir/dala_beam_flags
    let mut runtime_flags: Vec<String> = Vec::new();
    let flags_path = format!("{}/dala_beam_flags", beams_dir);
    if let Ok(contents) = std::fs::read_to_string(&flags_path) {
        runtime_flags = contents.split_whitespace().map(|s| s.to_string()).collect();
        android_log!(
            "dala_start_beam: loaded {} runtime flags from {}",
            runtime_flags.len(),
            flags_path
        );
    }

    // Select which flags to use
    let flags_to_use: Vec<&str> = if !runtime_flags.is_empty() {
        runtime_flags.iter().map(|s| s.as_str()).collect()
    } else {
        default_flags.to_vec()
    };

    let boot_path = format!("{}/releases/29/start_clean", otp_root);

    // Build args using CString for proper null-terminated strings
    let mut args: Vec<CString> = vec![CString::new("beam").unwrap()];

    for flag in &flags_to_use {
        args.push(CString::new(*flag).unwrap());
    }

    args.push(CString::new("--").unwrap());
    args.push(CString::new("-root").unwrap());
    args.push(CString::new(otp_root.as_str()).unwrap());
    args.push(CString::new("-bindir").unwrap());
    args.push(CString::new(bindir.as_str()).unwrap());
    args.push(CString::new("-progname").unwrap());
    args.push(CString::new("erl").unwrap());
    args.push(CString::new("--").unwrap());
    args.push(CString::new("-noshell").unwrap());
    args.push(CString::new("-noinput").unwrap());
    args.push(CString::new("-boot").unwrap());
    args.push(CString::new(boot_path.as_str()).unwrap());
    args.push(CString::new("-pa").unwrap());
    args.push(CString::new(elixir_dir.as_str()).unwrap());
    args.push(CString::new("-pa").unwrap());
    args.push(CString::new(logger_dir.as_str()).unwrap());
    args.push(CString::new("-pa").unwrap());
    args.push(CString::new(eex_dir.as_str()).unwrap());
    args.push(CString::new("-pa").unwrap());
    args.push(CString::new(beams_dir.as_str()).unwrap());
    args.push(CString::new("-eval").unwrap());
    args.push(CString::new(eval_expr.as_str()).unwrap());

    // Cold-start race condition fix: wait for window focus
    wait_for_window_focus();

    set_startup_phase("Starting BEAM…");
    android_log!(
        "dala_start_beam: starting BEAM with module={}, argc={}",
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
                android_log!("dala_start_beam: symlink {} -> {}", exe, lib_path);
            }
        }
    }

    // Convert args to raw pointers for erl_start
    let mut argv: Vec<*mut c_char> = args.iter().map(|s| s.as_ptr() as *mut c_char).collect();

    // Call erl_start (external C function from ERTS)
    unsafe {
        erl_start(args.len() as c_int, argv.as_mut_ptr());
    }
}

// ── Global JVM/Activity access for dala_nif ──────────────────────────────

/// Global JVM pointer - used by dala_nif to get JNI environment
#[no_mangle]
pub static mut G_JVM: *mut c_void = ptr::null_mut();

/// Global Activity pointer - used by dala_nif for UI operations
#[no_mangle]
pub static mut G_ACTIVITY: *mut c_void = ptr::null_mut();

/// JNI_OnLoad - called when the library is loaded
/// Sets up global JVM and Activity references for dala_nif
#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn JNI_OnLoad(vm: *mut jni::sys::JavaVM, _reserved: *mut c_void) -> jni::sys::jint {
    // Store the JVM pointer for dala_nif
    unsafe {
        G_JVM = vm as *mut c_void;
    }

    // Initialize logging
    #[cfg(target_os = "android")]
    {
        android_logger::init_once(
            android_logger::Config::default()
                .with_min_level(log::Level::Info)
                .with_tag("DalaBeam"),
        );
    }

    android_log!("JNI_OnLoad: initialized");

    jni::sys::JNI_VERSION_1_6
}

// Re-export header functions
pub use header::*;
