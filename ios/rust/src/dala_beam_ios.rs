// dala_beam_ios.rs — Complete Dala BEAM launcher for iOS.
// Full Rust port of dala_beam.m with erl_start binding

use std::ffi::{c_char, c_void, CStr, CString};
use std::fs;
use std::io::Write;
use std::os::raw::c_int;
use std::path::PathBuf;
use std::ptr;
use std::sync::Mutex;
use std::time::Duration;

// Mutex to protect std::env::set_var (not thread-safe)
static ENV_MUTEX: Mutex<()> = Mutex::new(());

const ERTS_VSN: &str = "erts-16.3";
const OTP_RELEASE: &str = "29";
const OTP_ROOT_LEGACY: &str = "/tmp/otp-ios-sim";

// EPMD compiled into the binary for device builds
#[cfg(all(feature = "dala_bundle_otp", not(feature = "dala_release")))]
extern "C" {
    fn epmd_ios_main(argc: c_int, argv: *mut *mut c_char) -> c_int;
}

// erl_start binding - Link with ERTS
// This function is provided by the BEAM runtime (libbeam.a)
extern "C" {
    fn erl_start(argc: c_int, argv: *mut *mut c_char);
}

// dala_set_startup_phase/error are implemented in dala_nif.rs
extern "C" {
    fn dala_set_startup_phase(phase: *const c_char);
    fn dala_set_startup_error(error: *const c_char);
}

// Logging macro for iOS
macro_rules! logi {
    ($fmt:expr $(, $args:expr)*) => {
        println!("[DalaBeam] {}", format!($fmt $(, $args)*));
    };
}

// Resolve the simulator's OTP runtime root at startup
fn resolve_sim_otp_root() -> PathBuf {
    if let Ok(env) = std::env::var("DALA_SIM_RUNTIME_DIR") {
        if !env.is_empty() {
            return PathBuf::from(env);
        }
    }
    // Check if legacy path exists
    let legacy = PathBuf::from(OTP_ROOT_LEGACY);
    if legacy.exists() {
        return legacy;
    }
    // Fallback to legacy path even if it doesn't exist
    legacy
}

#[no_mangle]
pub extern "C" fn dala_init_ui() {
    println!("[DalaBeam] dala_init_ui: SwiftUI mode ready");
}

// Write diagnostic file
fn dala_write_diag(docs_dir: &str, name: &str, info: &str) {
    let path = PathBuf::from(docs_dir).join(name);
    if let Ok(mut file) = fs::File::create(path) {
        let _ = writeln!(file, "{}", info);
    }
}

// Find link-local IP (169.254.x.x) for USB connectivity
#[cfg(all(feature = "dala_bundle_otp", not(target_os = "simulator")))]
fn find_link_local_ip() -> Option<String> {
    use std::net::Ipv4Addr;

    let mut ifa_list: *mut libc::ifaddrs = ptr::null_mut();
    unsafe {
        if getifaddrs(&mut ifa_list) != 0 {
            return None;
        }

        let mut found = None;
        let mut ifa = ifa_list;
        while !ifa.is_null() && found.is_none() {
            let ifa_ref = &*ifa;
            if !ifa_ref.ifa_addr.is_null() && (*ifa_ref.ifa_addr).sa_family as i32 == libc::AF_INET
            {
                let sa = &*(ifa_ref.ifa_addr as *const libc::sockaddr_in);
                let addr = u32::from_be(sa.sin_addr.s_addr);
                // Check if in 169.254.0.0/16
                if (addr >> 16) == 0xA9FE {
                    let ip = Ipv4Addr::new(
                        ((addr >> 24) & 0xFF) as u8,
                        ((addr >> 16) & 0xFF) as u8,
                        ((addr >> 8) & 0xFF) as u8,
                        (addr & 0xFF) as u8,
                    );
                    found = Some(ip.to_string());
                }
            }
            ifa = ifa_ref.ifa_next;
        }

        if !ifa_list.is_null() {
            freeifaddrs(ifa_list);
        }
        found
    }
}

// Find LAN IP (10.x, 172.16-31.x, 192.168.x, 100.64-127.x for Tailscale)
#[cfg(all(feature = "dala_bundle_otp", not(target_os = "simulator")))]
fn find_lan_ip() -> Option<String> {
    use std::net::Ipv4Addr;

    let mut ifa_list: *mut libc::ifaddrs = ptr::null_mut();
    unsafe {
        if getifaddrs(&mut ifa_list) != 0 {
            return None;
        }

        let mut found = None;
        let mut ifa = ifa_list;
        while !ifa.is_null() && found.is_none() {
            let ifa_ref = &*ifa;
            if !ifa_ref.ifa_addr.is_null() && (*ifa_ref.ifa_addr).sa_family as i32 == libc::AF_INET
            {
                let sa = &*(ifa_ref.ifa_addr as *const libc::sockaddr_in);
                let addr = u32::from_be(sa.sin_addr.s_addr);
                let top8 = addr >> 24;
                let top16 = addr >> 16;

                // 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10
                if top8 == 10
                    || (top16 >= 0xAC10 && top16 <= 0xAC1F)
                    || top16 == 0xC0A8
                    || (top16 >= 0x6440 && top16 <= 0x647F)
                {
                    let ip = Ipv4Addr::new(
                        ((addr >> 24) & 0xFF) as u8,
                        ((addr >> 16) & 0xFF) as u8,
                        ((addr >> 8) & 0xFF) as u8,
                        (addr & 0xFF) as u8,
                    );
                    found = Some(ip.to_string());
                }
            }
            ifa = ifa_ref.ifa_next;
        }

        if !ifa_list.is_null() {
            freeifaddrs(ifa_list);
        }
        found
    }
}

#[no_mangle]
pub extern "C" fn dala_start_beam(app_module: *const c_char) {
    let module = unsafe { CStr::from_ptr(app_module) }
        .to_str()
        .expect("Invalid app module name");

    logi!("dala_start_beam: starting for module {}", module);

    // Resolve Documents directory
    let docs_dir = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    dala_write_diag(
        &docs_dir,
        "dala_diag_a_entered.txt",
        "dala_start_beam entered",
    );

    // Determine OTP root
    #[cfg(feature = "dala_bundle_otp")]
    let otp_root = {
        // Device: OTP bundled in app bundle
        let bundle_otp = std::path::Path::new("/var/containers/Bundle/Application").join("otp");
        // Try to get actual bundle path
        if let Ok(bundle_path) = std::env::var("DALA_OTP_BUNDLE_PATH") {
            PathBuf::from(bundle_path)
        } else {
            bundle_otp
        }
    };

    #[cfg(not(feature = "dala_bundle_otp"))]
    let otp_root = resolve_sim_otp_root();

    let bindir = otp_root.join(ERTS_VSN).join("bin");
    let beams_dir = otp_root.join(module);
    let elixir_dir = otp_root.join("lib/elixir/ebin");
    let logger_dir = otp_root.join("lib/logger/ebin");
    let boot_path = otp_root
        .join("releases")
        .join(OTP_RELEASE)
        .join("start_clean");

    dala_write_diag(
        &docs_dir,
        "dala_diag_b_otp_root.txt",
        otp_root.to_str().expect("Failed to convert OTP root to string")
    );
    logi!(
        "otp_root={} erts={} release={}",
        otp_root.display(),
        ERTS_VSN,
        OTP_RELEASE
    );

    // Set environment variables (protected by mutex)
    {
        let _lock = ENV_MUTEX.lock().expect("Rust error");
        std::env::set_var("BINDIR", &bindir);
        std::env::set_var("ROOTDIR", &otp_root);
        std::env::set_var("PROGNAME", "erl");
        std::env::set_var("EMU", "beam");
        std::env::set_var("HOME", "/tmp");
        std::env::set_var("DALA_DATA_DIR", &docs_dir);

        let crash_dump = PathBuf::from(&docs_dir).join("dala_erl_crash.dump");
        std::env::set_var("ERL_CRASH_DUMP", crash_dump.to_str().expect("Failed to convert crash dump path to string"))
        std::env::set_var("ERL_CRASH_DUMP_SECONDS", "30");
    }

    // Distribution port
    let dist_port = std::env::var("DALA_DIST_PORT").unwrap_or_else(|_| "9101".to_string());

    // Determine node hostname
    #[cfg(feature = "dala_bundle_otp")]
    let host_ip = {
        // Device: WiFi/LAN -> USB link-local -> loopback
        let lan_ip = find_lan_ip();
        let link_local = if lan_ip.is_none() {
            find_link_local_ip()
        } else {
            None
        };
        lan_ip.unwrap_or_else(|| link_local.unwrap_or_else(|| "127.0.0.1".to_string()))
    };

    #[cfg(not(feature = "dala_bundle_otp"))]
    let host_ip = "127.0.0.1".to_string();

    let eval_expr = format!("{}:start().", module);

    #[cfg(feature = "dala_bundle_otp")]
    let node_name = {
        // Device: use IP-based name
        format!("{}_ios@{}", module, host_ip)
    };

    #[cfg(not(feature = "dala_bundle_otp"))]
    let node_name = {
        // Simulator: include UDID suffix for uniqueness
        let sim_udid = std::env::var("SIMULATOR_UDID").unwrap_or_default();
        let sim_short: String = sim_udid
            .chars()
            .filter(|c| c.is_ascii_hexdigit())
            .take(8)
            .collect::<String>()
            .to_lowercase();

        if !sim_short.is_empty() {
            format!("{}_ios_{}@{}", module, sim_short, host_ip)
        } else {
            format!("{}_ios@{}", module, host_ip)
        }
    };

    dala_write_diag(&docs_dir, "dala_diag_host_ip.txt", &host_ip);

    // Beams dir - check for Documents override on device
    #[cfg(feature = "dala_bundle_otp")]
    let beams_dir = {
        let docs_beams = PathBuf::from(&docs_dir).join("otp").join(module);
        if docs_beams.exists() {
            dala_write_diag(
                &docs_dir,
                "dala_diag_beams_dir.txt",
                docs_beams.to_str().expect("Rust error"),
            );
            docs_beams
        } else {
            beams_dir
        }
    };

    // Set DALA_BEAMS_DIR for Ecto migrations
    std::env::set_var("DALA_BEAMS_DIR", beams_dir.to_str().expect("Rust error"));

    // BEAM tuning flags
    let default_flags: &[&str] = &[
        "-S", "1:1", "-SDcpu", "1:1", "-SDio", "1", "-A", "1", "-sbwt", "none",
    ];

    // Runtime override from beams_dir/dala_beam_flags
    let flags_path = beams_dir.join("dala_beam_flags");
    let mut runtime_flags: Vec<String> = Vec::new();
    if let Ok(contents) = fs::read_to_string(&flags_path) {
        runtime_flags = contents.split_whitespace().map(|s| s.to_string()).collect();
        logi!(
            "loaded {} runtime flags from {:?}",
            runtime_flags.len(),
            flags_path
        );
    }

    // Build argv for erl_start
    let mut args: Vec<CString> = Vec::new();
    args.push(CString::new("beam").expect("Failed to create CString"));

    // Add flags
    if !runtime_flags.is_empty() {
        for flag in &runtime_flags {
            args.push(CString::new(flag.as_str()).expect("Failed to create flag CString"));
        }
    } else {
        for flag in default_flags {
            args.push(CString::new(*flag).expect("Failed to create default flag CString"));
        }
    }

    // Memory cap for device
    #[cfg(feature = "dala_bundle_otp")]
    {
        args.push(CString::new("-MIscs").expect("Failed to create CString"));
        args.push(CString::new("10").expect("Failed to create CString"));
    }

    args.push(CString::new("--").expect("Failed to create CString"));
    args.push(CString::new("-root").expect("Failed to create CString"));
    args.push(CString::new(&otp_root).expect("Failed to create OTP root CString"));
    args.push(CString::new("-bindir").expect("Failed to create CString"));
    args.push(CString::new(&bindir).expect("Failed to create bindir CString"));
    args.push(CString::new("-progname").expect("Failed to create CString"));
    args.push(CString::new("erl").expect("Failed to create CString"));
    args.push(CString::new("--").expect("Failed to create CString"));

    // Distribution flags (not for DALA_RELEASE)
    #[cfg(not(feature = "dala_release"))]
    {
        args.push(CString::new("-name").expect("Failed to create CString"));
        args.push(CString::new(&node_name).expect("Failed to create node name CString"));
        args.push(CString::new("-setcookie").expect("Failed to create CString"));
        args.push(CString::new("dala_secret").expect("Failed to create CString"));
        args.push(CString::new("-kernel").expect("Failed to create CString"));
        args.push(CString::new("inet_dist_listen_min").expect("Failed to create CString"));
        args.push(CString::new(&dist_port).expect("Failed to create dist port CString"));
        args.push(CString::new("-kernel").expect("Failed to create CString"));
        args.push(CString::new("inet_dist_listen_max").expect("Failed to create CString"));
        args.push(CString::new(&dist_port).expect("Failed to create dist port CString"));
    }

    #[cfg(feature = "dala_release")]
    {
        std::env::set_var("DALA_RELEASE", "1");
    }

    args.push(CString::new("-noshell").expect("Rust error"));
    args.push(CString::new("-noinput").expect("Rust error"));
    args.push(CString::new("-boot").expect("Rust error"));
    args.push(CString::new(boot_path.to_str().expect("Rust error")).expect("Rust error"));
    args.push(CString::new("-pa").expect("Rust error"));
    args.push(CString::new(elixir_dir.to_str().expect("Rust error")).expect("Rust error"));
    args.push(CString::new("-pa").expect("Rust error"));
    args.push(CString::new(logger_dir.to_str().expect("Rust error")).expect("Rust error"));
    args.push(CString::new("-pa").expect("Rust error"));
    args.push(CString::new(beams_dir.to_str().expect("Rust error")).expect("Rust error"));
    args.push(CString::new("-eval").expect("Rust error"));
    args.push(CString::new(&eval_expr).expect("Rust error"));
    // Properly NULL-terminate argv for erl_start
    args.push(CString::new("").expect("Rust error")); // placeholder, will be replaced with null ptr

    logi!("starting BEAM module={} argc={}", module, args.len());

    // Convert to argv with proper NULL terminator
    let mut argv: Vec<*mut c_char> = args.iter().map(|s| s.as_ptr() as *mut c_char).collect();
    // Replace the last element (empty string placeholder) with actual NULL terminator
    if let Some(last) = argv.last_mut() {
        *last = ptr::null_mut();
    }
    unsafe {
        let phase = CString::new("Starting BEAM…").expect("Rust error");
        dala_set_startup_phase(phase.as_ptr());
    }

    // Redirect stdout/stderr to log file
    let beam_log_path = PathBuf::from(&docs_dir).join("beam_stdout.log");
    if let Ok(log_fd) = std::fs::File::create(&beam_log_path) {
        let fd = log_fd.into_raw_fd();
        unsafe {
            libc::dup2(fd, libc::STDOUT_FILENO);
            libc::dup2(fd, libc::STDERR_FILENO);
            libc::close(fd);
        }
    }

    // Start EPMD thread for device builds (not release)
    #[cfg(all(feature = "dala_bundle_otp", not(feature = "dala_release")))]
    {
        std::thread::spawn(|| {
            let args = [CString::new("epmd").expect("Rust error")];
            let mut argv: Vec<*mut c_char> =
                args.iter().map(|s| s.as_ptr() as *mut c_char).collect();
            argv.push(ptr::null_mut());
            epmd_ios_main(1, argv.as_mut_ptr());
        });
        std::thread::sleep(Duration::from_millis(300));
    }

    // CALL ERL_START - This is where BEAM actually starts
    unsafe {
        let mut argv: Vec<*mut c_char> = args.iter().map(|s| s.as_ptr() as *mut c_char).collect();
        argv.push(ptr::null_mut());

        logi!(
            "dala_start_beam: calling erl_start with {} arguments",
            args.len() - 1
        );
        erl_start((args.len() - 1) as c_int, argv.as_mut_ptr());
    }

    // If we get here, erl_start returned (which is unexpected)
    dala_write_diag(&docs_dir, "dala_diag_e_erl_exited.txt", "erl_start returned");
    unsafe {
        let error =
            CString::new("BEAM exited unexpectedly — check Documents/dala_erl_crash.dump").expect("Rust error");
        dala_set_startup_error(error.as_ptr());
    }
    logi!("dala_start_beam: erl_start returned (unexpected)");
}

#[no_mangle]
pub extern "C" fn dala_send_push_token(_hex_token: *const c_char) {
    // Implementation for push token forwarding
}

#[no_mangle]
pub extern "C" fn dala_set_launch_notification_json(_json: *const c_char) {
    // Implementation for storing launch notification
}

// Link with required system libraries for iOS
#[link(name = "Foundation", kind = "framework")]
#[link(name = "UIKit", kind = "framework")]
extern "C" {}

// Need to import these for ifaddrs
extern "C" {
    fn getifaddrs(ifap: *mut *mut libc::ifaddrs) -> c_int;
    fn freeifaddrs(ifa: *mut libc::ifaddrs);
}
