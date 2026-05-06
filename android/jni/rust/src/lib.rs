// lib.rs - Dala BEAM launcher and JNI bridge initialization for Android
// This is the Android-specific crate that provides:
// - Static driver/NIF tables for ERTS
// - JNI bridge functions called from Java/Kotlin
// - BEAM startup orchestration
// - Event sender stubs (implemented in dala_nif)

mod driver_tab;
mod header;

use jni::objects::{JClass, JObject, JString};
use jni::JavaVM;
use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::Mutex;

// Re-export the driver table and NIF table for ERTS linking
pub use driver_tab::{driver_tab, erts_init_static_drivers, erts_static_nif_tab};

// Re-export header functions (event senders, etc.)
pub use header::*;

// ── Global State ─────────────────────────────────────────────────────────

// Thread-safe JVM storage - jni::JavaVM is Send + Sync
static JVM: Mutex<Option<JavaVM>> = Mutex::new(None);
static ACTIVITY: Mutex<Option<*mut c_void>> = Mutex::new(None);
static NATIVE_LIB_DIR: Mutex<String> = Mutex::new(String::new());
static FILES_DIR: Mutex<String> = Mutex::new(String::new());

// ERTS version - must match the OTP release
const ERTS_VSN: &str = "erts-16.3";

// ── Logging Helper ───────────────────────────────────────────────────────

fn log_info(msg: &str) {
    #[cfg(target_os = "android")]
    {
        android_logger::init_once(
            android_logger::Config::default()
                .with_min_level(log::Level::Info)
                .with_tag("DalaBeam"),
        );
        log::info!("{}", msg);
    }
    #[cfg(not(target_os = "android"))]
    {
        println!("[DalaBeam] {}", msg);
    }
}

macro_rules! log_info {
    ($($arg:tt)*) => {
        log_info(&format!($($arg)*));
    };
}

// ── JNI_OnLoad ───────────────────────────────────────────────────────────

/// Called when the native library is loaded by the JVM.
/// Stores the JavaVM pointer for later use.
#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn JNI_OnLoad(vm: *mut jni::sys::JavaVM, _reserved: *mut c_void) -> jni::sys::jint {
    log_info!("JNI_OnLoad: initializing");

    // Convert raw pointer to jni::JavaVM safely
    let jvm = unsafe { JavaVM::from_raw(vm) };
    if let Ok(jvm) = jvm {
        let mut guard = JVM.lock().unwrap();
        *guard = Some(jvm);
        log_info!("JNI_OnLoad: JavaVM stored successfully");
    } else {
        log_info!("JNI_OnLoad: WARNING - failed to wrap JavaVM pointer");
    }

    jni::sys::JNI_VERSION_1_6
}

// ── JNI Bridge Functions ─────────────────────────────────────────────────

/// Called from Java to cache the bridge class for callbacks.
/// bridge_class: fully qualified class name (e.g., "com/myapp/DalaBridge")
#[no_mangle]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeUiCacheClass(
    env: jni::JNIEnv,
    _class: JClass,
    bridge_class: JString,
) {
    let class_str = env.get_string(bridge_class.into());
    if let Ok(s) = class_str {
        let class_name = s.to_string_lossy();
        log_info!("nativeUiCacheClass: {}", class_name);
        // TODO: Call dala_nif to cache the class for callbacks
    }
}

/// Called from Java to initialize the bridge with the Activity context.
/// Extracts nativeLibraryDir and filesDir for BEAM startup.
#[no_mangle]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeInitBridge(
    env: jni::JNIEnv,
    _class: JClass,
    activity: JObject,
) {
    log_info!("nativeInitBridge: initializing");

    // Store JVM
    if let Ok(jvm) = env.get_java_vm() {
        let mut guard = JVM.lock().unwrap();
        *guard = Some(jvm);
    }

    // Get nativeLibraryDir from ApplicationInfo
    let ctx_cls = match env.find_class("android/content/Context") {
        Ok(c) => c,
        Err(_) => {
            log_info!("nativeInitBridge: ERROR - failed to find Context class");
            return;
        }
    };

    let app_info = match env.call_method(
        &activity,
        "getApplicationInfo",
        "()Landroid/content/pm/ApplicationInfo;",
        &[],
    ) {
        Ok(r) => match r.l() {
            Ok(obj) => obj,
            Err(_) => {
                log_info!("nativeInitBridge: ERROR - failed to get ApplicationInfo");
                return;
            }
        },
        Err(_) => {
            log_info!("nativeInitBridge: ERROR - getApplicationInfo call failed");
            return;
        }
    };

    let app_info_cls = match env.find_class("android/content/pm/ApplicationInfo") {
        Ok(c) => c,
        Err(_) => {
            log_info!("nativeInitBridge: ERROR - failed to find ApplicationInfo class");
            return;
        }
    };

    // Get nativeLibraryDir field
    let native_lib_dir = match env.get_field(&app_info, "nativeLibraryDir", "Ljava/lang/String;") {
        Ok(f) => match f.l() {
            Ok(obj) => {
                let jstr: JString = obj.into();
                match env.get_string(jstr) {
                    Ok(s) => s.to_string_lossy().to_string(),
                    Err(_) => {
                        log_info!(
                            "nativeInitBridge: ERROR - failed to get nativeLibraryDir string"
                        );
                        return;
                    }
                }
            }
            Err(_) => {
                log_info!("nativeInitBridge: ERROR - nativeLibraryDir field is null");
                return;
            }
        },
        Err(_) => {
            log_info!("nativeInitBridge: ERROR - failed to get nativeLibraryDir field");
            return;
        }
    };

    {
        let mut guard = NATIVE_LIB_DIR.lock().unwrap();
        *guard = native_lib_dir.clone();
    }
    log_info!("nativeInitBridge: nativeLibraryDir = {}", native_lib_dir);

    // Get filesDir from Context
    let files_dir_obj = match env.call_method(&activity, "getFilesDir", "()Ljava/io/File;", &[]) {
        Ok(r) => match r.l() {
            Ok(obj) => obj,
            Err(_) => {
                log_info!("nativeInitBridge: ERROR - getFilesDir returned null");
                return;
            }
        },
        Err(_) => {
            log_info!("nativeInitBridge: ERROR - getFilesDir call failed");
            return;
        }
    };

    let file_cls = match env.find_class("java/io/File") {
        Ok(c) => c,
        Err(_) => {
            log_info!("nativeInitBridge: ERROR - failed to find File class");
            return;
        }
    };

    let files_dir = match env.call_method(&files_dir_obj, "getPath", "()Ljava/lang/String;", &[]) {
        Ok(r) => match r.l() {
            Ok(obj) => {
                let jstr: JString = obj.into();
                match env.get_string(jstr) {
                    Ok(s) => s.to_string_lossy().to_string(),
                    Err(_) => {
                        log_info!("nativeInitBridge: ERROR - failed to get filesDir string");
                        return;
                    }
                }
            }
            Err(_) => {
                log_info!("nativeInitBridge: ERROR - getPath returned null");
                return;
            }
        },
        Err(_) => {
            log_info!("nativeInitBridge: ERROR - getPath call failed");
            return;
        }
    };

    {
        let mut guard = FILES_DIR.lock().unwrap();
        *guard = files_dir.clone();
    }
    log_info!("nativeInitBridge: filesDir = {}", files_dir);

    // Store activity as raw pointer (for callbacks)
    let activity_ptr = env.new_global_ref(&activity);
    if let Ok(ref activity_global) = activity_ptr {
        // We can't store JObject<'static> directly, but we can store the raw pointer
        // and reconstitute it when needed
        let mut guard = ACTIVITY.lock().unwrap();
        *guard = Some(activity_global.as_obj().as_raw() as *mut c_void);
    }

    log_info!("nativeInitBridge: complete");
}

/// Called from Java to start the BEAM VM.
/// app_module: Elixir module name to start (e.g., "my_app")
#[no_mangle]
pub extern "C" fn Java_com_example_dala_DalaBridge_nativeStartBeam(
    env: jni::JNIEnv,
    _class: JClass,
    app_module: JString,
) {
    let module = env.get_string(app_module.into());
    if let Ok(s) = module {
        let app_module_str = s.to_string_lossy().to_string();
        log_info!("nativeStartBeam: module = {}", app_module_str);
        start_beam(&app_module_str);
    } else {
        log_info!("nativeStartBeam: ERROR - failed to get app_module string");
    }
}

// ── BEAM Startup ──────────────────────────────────────────────────────────

fn start_beam(app_module: &str) {
    // Check NO_BEAM feature flag
    #[cfg(feature = "no_beam")]
    {
        log_info!("start_beam: NO_BEAM feature enabled, skipping BEAM launch");
        return;
    }

    set_startup_phase("Setting up BEAM environment…");

    // Get paths from global state
    let files_dir = FILES_DIR.lock().unwrap().clone();
    let native_lib_dir = NATIVE_LIB_DIR.lock().unwrap().clone();

    if files_dir.is_empty() {
        log_info!("start_beam: ERROR - filesDir not set, call nativeInitBridge first");
        set_startup_error("filesDir not initialized");
        return;
    }

    // Build paths
    let otp_root = format!("{}/otp", files_dir);
    let bindir = format!("{}/{}/bin", otp_root, ERTS_VSN);
    let beams_dir = format!("{}/{}", otp_root, app_module);
    let elixir_dir = format!("{}/lib/elixir/ebin", otp_root);
    let logger_dir = format!("{}/lib/logger/ebin", otp_root);
    let eex_dir = format!("{}/lib/eex/ebin", otp_root);
    let crash_dump = format!("{}/erl_crash.dump", files_dir);

    // Set environment variables for BEAM
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

    // BEAM tuning flags based on feature
    let flags: Vec<&str> = if cfg!(feature = "beam_untuned") {
        vec![]
    } else if cfg!(feature = "beam_sbwt_only") {
        vec!["-sbwt", "none", "-sbwtdcpu", "none", "-sbwtdio", "none"]
    } else {
        // Default: BEAM_FULL_NERVES (optimized for mobile)
        vec![
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

    // Check for runtime flags file
    let flags_path = format!("{}/dala_beam_flags", beams_dir);
    let runtime_flags: Vec<String> = if let Ok(contents) = std::fs::read_to_string(&flags_path) {
        let flags: Vec<String> = contents.split_whitespace().map(|s| s.to_string()).collect();
        log_info!(
            "start_beam: loaded {} runtime flags from {}",
            flags.len(),
            flags_path
        );
        flags
    } else {
        vec![]
    };

    let boot_path = format!("{}/releases/29/start_clean", otp_root);

    // Build argument vector
    let mut args: Vec<String> = vec!["beam".to_string()];
    args.extend(flags.iter().map(|s| s.to_string()));
    args.push("--".to_string());
    args.push("-root".to_string());
    args.push(otp_root.clone());
    args.push("-bindir".to_string());
    args.push(bindir.clone());
    args.push("-progname".to_string());
    args.push("erl".to_string());
    args.push("--".to_string());
    args.push("-noshell".to_string());
    args.push("-noinput".to_string());
    args.push("-boot".to_string());
    args.push(boot_path);
    args.push("-pa".to_string());
    args.push(elixir_dir);
    args.push("-pa".to_string());
    args.push(logger_dir);
    args.push("-pa".to_string());
    args.push(eex_dir);
    args.push("-pa".to_string());
    args.push(beams_dir.clone());
    args.push("-eval".to_string());
    args.push(eval_expr);

    // If runtime flags exist, use them instead
    if !runtime_flags.is_empty() {
        // Rebuild args with runtime flags
        args = vec!["beam".to_string()];
        args.extend(runtime_flags);
        args.push("--".to_string());
        args.push("-root".to_string());
        args.push(otp_root.clone());
        args.push("-bindir".to_string());
        args.push(bindir.clone());
        args.push("-progname".to_string());
        args.push("erl".to_string());
        args.push("--".to_string());
        args.push("-noshell".to_string());
        args.push("-noinput".to_string());
        args.push("-boot".to_string());
        args.push(format!("{}/releases/29/start_clean", otp_root));
        args.push("-pa".to_string());
        args.push(format!("{}/lib/elixir/ebin", otp_root));
        args.push("-pa".to_string());
        args.push(format!("{}/lib/logger/ebin", otp_root));
        args.push("-pa".to_string());
        args.push(format!("{}/lib/eex/ebin", otp_root));
        args.push("-pa".to_string());
        args.push(beams_dir);
        args.push("-eval".to_string());
        args.push(format!("{}:start().", app_module));
    }

    // Symlink ERTS executables (Android loads .so files, not executables)
    if !native_lib_dir.is_empty() {
        let exes = [
            ("erl_child_setup", "liberl_child_setup.so"),
            ("inet_gethost", "libinet_gethost.so"),
            ("epmd", "libepmd.so"),
        ];
        for (exe, lib) in exes {
            let bin_path = format!("{}/{}/bin/{}", otp_root, ERTS_VSN, exe);
            let lib_path = format!("{}/{}", native_lib_dir, lib);
            let _ = std::fs::remove_file(&bin_path);
            if std::os::unix::fs::symlink(&lib_path, &bin_path).is_ok() {
                log_info!("start_beam: symlinked {} -> {}", exe, lib_path);
            }
        }
    }

    // Wait for window focus (cold-start race condition fix)
    wait_for_window_focus();

    set_startup_phase("Starting BEAM…");
    log_info!("start_beam: launching BEAM with {} args", args.len());

    // Convert args to C-style for erl_start
    let c_args: Vec<std::ffi::CString> = args
        .iter()
        .map(|s| std::ffi::CString::new(s.as_str()).unwrap())
        .collect();
    let mut c_argv: Vec<*mut c_char> = c_args.iter().map(|s| s.as_ptr() as *mut c_char).collect();

    // Call erl_start (external C function from ERTS)
    extern "C" {
        fn erl_start(argc: c_int, argv: *mut *mut c_char);
    }

    unsafe {
        erl_start(c_argv.len() as c_int, c_argv.as_mut_ptr());
    }
}

// ── Startup Phase/Error Reporting ─────────────────────────────────────────

/// Report startup phase to Java (shows in UI)
fn set_startup_phase(phase: &str) {
    log_info!("startup phase: {}", phase);

    // Call back to Java to update UI
    let jvm_guard = JVM.lock().unwrap();
    if let Some(ref jvm) = *jvm_guard {
        if let Ok(env) = jvm.attach_current_thread() {
            // Find the DalaBridge class and call setStartupPhase
            if let Ok(cls) = env.find_class("com/example/dala/DalaBridge") {
                let phase_str = env.new_string(phase);
                if let Ok(p) = phase_str {
                    let _ = env.call_static_method(
                        cls,
                        "setStartupPhase",
                        "(Ljava/lang/String;)V",
                        &[(&p).into()],
                    );
                }
            }
        }
    }
}

/// Report startup error to Java (shows error screen)
fn set_startup_error(error: &str) {
    log_info!("startup error: {}", error);

    // Call back to Java to show error
    let jvm_guard = JVM.lock().unwrap();
    if let Some(ref jvm) = *jvm_guard {
        if let Ok(env) = jvm.attach_current_thread() {
            if let Ok(cls) = env.find_class("com/example/dala/DalaBridge") {
                let error_str = env.new_string(error);
                if let Ok(e) = error_str {
                    let _ = env.call_static_method(
                        cls,
                        "setStartupError",
                        "(Ljava/lang/String;)V",
                        &[(&e).into()],
                    );
                }
            }
        }
    }
}

/// Wait for window focus before starting BEAM (fixes cold-start race)
fn wait_for_window_focus() {
    // TODO: Implement proper window focus wait
    // For now, just a small delay
    std::thread::sleep(std::time::Duration::from_millis(100));
}

// ── C-compatible startup functions ────────────────────────────────────────

/// C-compatible startup phase setter
#[no_mangle]
pub extern "C" fn dala_set_startup_phase(phase: *const c_char) {
    if phase.is_null() {
        return;
    }
    let phase_str = unsafe { CStr::from_ptr(phase) };
    if let Ok(s) = phase_str.to_str() {
        set_startup_phase(s);
    }
}

/// C-compatible startup error setter
#[no_mangle]
pub extern "C" fn dala_set_startup_error(error: *const c_char) {
    if error.is_null() {
        return;
    }
    let error_str = unsafe { CStr::from_ptr(error) };
    if let Ok(s) = error_str.to_str() {
        set_startup_error(s);
    }
}

/// C-compatible BEAM starter (called from native code)
#[no_mangle]
pub extern "C" fn dala_start_beam(app_module: *const c_char) {
    if app_module.is_null() {
        log_info!("dala_start_beam: ERROR - null app_module");
        return;
    }
    let module_str = unsafe { CStr::from_ptr(app_module) };
    if let Ok(s) = module_str.to_str() {
        start_beam(s);
    }
}
