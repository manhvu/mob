# Build & BEAM Loading Guide

Complete guide on how Dala apps are built, deployed, and how the BEAM runtime loads on iOS and Android devices.

## Table of Contents

1. [Overview](#overview)
2. [Build Process](#build-process)
   - [iOS Build](#ios-build)
   - [Android Build](#android-build)
3. [BEAM Loading on iOS](#beam-loading-on-ios)
   - [Simulator vs Device](#simulator-vs-device)
   - [OTP Preparation](#otp-preparation)
   - [Starting the BEAM](#starting-the-beam)
4. [BEAM Loading on Android](#beam-loading-on-android)
   - [Native Library Setup](#native-library-setup)
   - [JNI Bridge](#jni-bridge)
   - [Starting the BEAM](#starting-the-beam-1)
5. [Erlang Distribution](#erlang-distribution)
6. [Troubleshooting](#troubleshooting)

---

## Overview

Dala apps embed a full Erlang/OTP runtime (BEAM) directly in the mobile app. The BEAM runs as an in-process VM, not a separate process. This architecture enables:

- **Hot code reloading** via Erlang distribution (no app restart needed)
- **Real GenServers** driving UI state on-device
- **Full BEAM introspection** (`:observer`, `Node.connect/1`)
- **Cross-platform consistency** (same Elixir code on all platforms)

```
┌─────────────────────────────────────────────┐
│           Mobile App (iOS/Android)          │
│  ┌───────────────────────────────────────┐  │
│  │  Native UI (SwiftUI / Jetpack Compose)│  │
│  └───────────────┬───────────────────────┘  │
│                  │ JSON/Binary                │
│  ┌───────────────▼───────────────────────┐  │
│  │  Rust NIF (dala_nif, dala_beam)       │  │
│  └───────────────┬───────────────────────┘  │
│                  │ erl_start()               │
│  ┌───────────────▼───────────────────────┐  │
│  │  BEAM VM (libbeam.a, static NIFs)    │  │
│  │  - Elixir app code (.beam files)      │  │
│  │  - OTP apps (kernel, stdlib, etc.)    │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

---

## Build Process

### iOS Build

iOS builds use two separate paths for simulator and device, handled by `dala_dev`:

| Target | Script | Called by |
|--------|--------|-----------|
| Simulator (x86_64/arm64) | `ios/rust/build_ios.sh` | `DalaDev.NativeBuild.build_ios/1` |
| Physical Device (arm64) | `ios/build_device.sh` | `DalaDev.NativeBuild.build_ios_physical/2` |

#### Simulator Build

The simulator shares the Mac's network stack and `/tmp` directory, simplifying development:

```bash
# Build Rust NIFs for simulator targets
cd dala/ios/rust
./build_ios.sh

# This produces:
# - target/aarch64-apple-ios-sim/release/libdala_beam_ios.a
# - target/x86_64-apple-ios/release/libdala_beam_ios.a
```

The simulator build:
- Links dynamically with OTP from `/tmp/otp-ios-sim`
- Uses standard EPMD (Mac's EPMD is reachable)
- Doesn't require static NIF registration (can `dlopen` `.so` files)

#### Device Build

Physical iOS devices require a completely different approach due to sandboxing:

1. **Build OTP from source** for `aarch64-apple-ios`:
   ```bash
   cd /tmp/otp_ios_device_build
   git clone https://github.com/erlang/otp.git
   cd otp && git checkout OTP-28.1
   
   ./otp_build autoconf
   ./configure \
     --host=aarch64-apple-ios \
     --build=arm64-apple-darwin \
     --with-ssl=no \
     --disable-jit \          # W^X policy blocks JIT on iOS
     --disable-esock \        # net/if_arp.h missing from iOS SDK
     --without-asn1 \
     --without-runtime_tools \
     --without-os_mon
   
   make -j$(sysctl -n hw.ncpu)
   ```

2. **Bundle OTP inside the `.app`**:
   ```
   YourApp.app/
     ├── otp/                      ← Bundled OTP runtime
     │   ├── erts-16.3/
     │   ├── lib/                  ← OTP apps (kernel, stdlib, elixir, etc.)
     │   └── releases/
     ├── Frameworks/
     │   └── YourApp.framework/
     └── Info.plist
   ```

3. **Static NIF registration** in `driver_tab_ios.rs`:
   ```rust
   // All NIFs must be statically linked, not dlopen'd
   #[no_mangle]
   pub static mut erts_static_nif_tab: [ErtsStaticNif; 11] = [
       // ... ERTS built-in NIFs ...
       ErtsStaticNif {
           nif_init: Some(dala_nif_nif_init),  // dala_nif
           is_builtin: 0,
           nif_mod: THE_NON_VALUE,
           entry: std::ptr::null_mut(),
       },
       // ... NULL-terminated ...
   ];
   ```

4. **EPMD as in-process thread** (device only):
   ```rust
   // epmd is compiled into the app binary with renamed main()
   extern "C" {
       fn epmd_ios_main(argc: c_int, argv: *mut *mut c_char) -> c_int;
   }
   
   // Start on a pthread before erl_start()
   std::thread::spawn(|| {
       let args = [CString::new("epmd").unwrap()];
       let mut argv: Vec<*mut c_char> = args.iter().map(|s| s.as_ptr() as *mut c_char).collect();
       argv.push(ptr::null_mut());
       epmd_ios_main(1, argv.as_mut_ptr());
   });
   std::thread::sleep(Duration::from_millis(300));
   ```

### Android Build

Android builds use Rust with the Android NDK:

```bash
cd dala/android/jni/rust
./build_android.sh

# This produces .so files for:
# - aarch64-linux-android (ARM64)
# - armv7-linux-androideabi (ARM32)
# - x86_64-linux-android (x86_64 emulator)
# - i686-linux-android (x86 emulator)
```

The Android build:
- Produces shared libraries (`.so`) loaded by the Java `DalaBridge`
- Uses JNI (Java Native Interface) for Java ↔ Rust communication
- Symlinks ERTS executables (`erl_child_setup`, `epmd`, `inet_gethost`) from `nativeLibraryDir`

Key build flags in `build_android.sh`:
```bash
# NDK toolchain setup
TARGET_LINKER="${ANDROID_NDK}/toolchains/llvm/prebuilt/${NDK_HOST}/bin/${target}-clang"
export "CARGO_TARGET_${TARGET_UPPER}_LINKER=$TARGET_LINKER"

# Build with optional features
cargo build --target "$target" --release --features "$FEATURES"
```

---

## BEAM Loading on iOS

### Simulator vs Device

| Aspect | Simulator | Physical Device |
|--------|-----------|-----------------|
| OTP Location | `/tmp/otp-ios-sim` | Bundled in `.app/otp/` |
| EPMD | Uses Mac's EPMD | In-process thread |
| NIF Loading | `dlopen` (dynamic) | Static table (`erts_static_nif_tab`) |
| Memory | Default (1GB super carrier) | Capped (`-MIscs 10`) |
| JIT | Enabled (Mac allows it) | Disabled (W^X policy) |
| Network | Shared with Mac | Device's own IP |

### OTP Preparation

#### Simulator

OTP lives at a fixed path accessible to both the Mac and simulator:
```rust
fn resolve_sim_otp_root() -> PathBuf {
    // Check DALA_SIM_RUNTIME_DIR env var first
    if let Ok(env) = std::env::var("DALA_SIM_RUNTIME_DIR") {
        return PathBuf::from(env);
    }
    // Fallback to legacy path
    PathBuf::from("/tmp/otp-ios-sim")
}
```

#### Device

OTP must be bundled inside the app and resolved at runtime:
```rust
#[cfg(feature = "dala_bundle_otp")]
let otp_root = {
    // OTP is bundled in the app bundle
    let bundle_otp = std::path::Path::new("/var/containers/Bundle/Application")
        .join("otp");
    
    // Or use env var set by ObjC bridge
    if let Ok(bundle_path) = std::env::var("DALA_OTP_BUNDLE_PATH") {
        PathBuf::from(bundle_path)
    } else {
        bundle_otp
    }
};
```

### Starting the BEAM

The BEAM starts when `erl_start()` is called from Rust. Here's the iOS flow:

```rust
#[no_mangle]
pub extern "C" fn dala_start_beam(app_module: *const c_char) {
    let module = /* convert C string to Rust str */;
    
    // 1. Set environment variables
    std::env::set_var("BINDIR", &bindir);
    std::env::set_var("ROOTDIR", &otp_root);
    std::env::set_var("PROGNAME", "erl");
    std::env::set_var("EMU", "beam");
    std::env::set_var("HOME", "/tmp");
    std::env::set_var("ERL_CRASH_DUMP", crash_dump_path);
    
    // 2. Build argv for erl_start
    let mut args: Vec<CString> = vec![
        CString::new("beam").unwrap(),
        CString::new("-root").unwrap(),
        CString::new(otp_root.to_str().unwrap()).unwrap(),
        CString::new("-bindir").unwrap(),
        CString::new(bindir.to_str().unwrap()).unwrap(),
        // ... more flags ...
        CString::new("-eval").unwrap(),
        CString::new(format!("{}:start().", module)).unwrap(),
    ];
    
    // 3. Start EPMD thread (device only)
    #[cfg(all(feature = "dala_bundle_otp", not(feature = "dala_release")))]
    {
        std::thread::spawn(|| { epmd_ios_main(1, argv); });
        std::thread::sleep(Duration::from_millis(300));
    }
    
    // 4. CALL ERL_START - This blocks until BEAM stops
    unsafe {
        let mut argv: Vec<*mut c_char> = args.iter()
            .map(|s| s.as_ptr() as *mut c_char)
            .collect();
        argv.push(ptr::null_mut());
        
        erl_start((args.len() - 1) as c_int, argv.as_mut_ptr());
    }
    
    // If we get here, BEAM exited (unexpected)
}
```

Key `erl_start` arguments:
```rust
// BEAM tuning flags (from dala_beam_ios.rs)
let default_flags: &[&str] = &[
    "-S", "1:1",           // Schedulers: 1 online, 1 dirty
    "-SDcpu", "1:1",       // Dirty CPU schedulers
    "-SDio", "1",          // Dirty I/O schedulers
    "-A", "1",             // Async threads
    "-sbwt", "none",       // No busy wait
];

// Memory cap for device (prevents iOS killing the app)
#[cfg(feature = "dala_bundle_otp")]
{
    args.push(CString::new("-MIscs").unwrap());  // Super carrier size
    args.push(CString::new("10").unwrap());     // 10 MB (default is 1 GB)
}

// Distribution flags
args.push(CString::new("-name").unwrap());
args.push(CString::new(&node_name).unwrap());  // e.g., "myapp_ios@127.0.0.1"
args.push(CString::new("-setcookie").unwrap());
args.push(CString::new("dala_secret").unwrap());
```

---

## BEAM Loading on Android

### Native Library Setup

On Android, the BEAM loads via JNI (Java Native Interface):

```java
// DalaBridge.java
public class DalaBridge {
    static {
        // Load the Rust NIF library
        System.loadLibrary("dala_beam");
    }
    
    public native void nativeInitBridge(Activity activity);
    public native void nativeStartBeam(String appModule);
}
```

When `System.loadLibrary("dala_beam")` is called, the JVM calls `JNI_OnLoad`:

```rust
#[no_mangle]
#[allow(non_snake_case)]
pub extern "C" fn JNI_OnLoad(vm: *mut JavaVM, _reserved: *mut c_void) -> jint {
    // Store JVM pointer for later use by dala_nif
    unsafe {
        G_JVM = vm as *mut c_void;
    }
    
    // Initialize logging
    android_logger::init_once(
        android_logger::Config::default()
            .with_min_level(log::Level::Info)
            .with_tag("DalaBeam"),
    );
    
    jni::sys::JNI_VERSION_1_6
}
```

### JNI Bridge

The JNI bridge initializes the Android environment and starts the BEAM:

```rust
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
    
    // Cache the Activity as a global reference
    if let Ok(global_ref) = env.new_global_ref(&activity) {
        let mut guard = ACTIVITY.lock().unwrap();
        *guard = Some(global_ref);
    }
    
    // Get nativeLibraryDir from ApplicationInfo
    let app_info = env.call_method(&activity, "getApplicationInfo", "()Landroid/content/pm/ApplicationInfo;", &[])
        .unwrap().l().unwrap();
    let jdir = env.get_field(&app_info, "nativeLibraryDir", "Ljava/lang/String;")
        .unwrap().l().unwrap();
    let native_lib_dir = env.get_string(&JString::from(jdir)).unwrap().to_string_lossy().to_string();
    
    // Store for later use (symlinking ERTS executables)
    *NATIVE_LIB_DIR.lock().unwrap() = native_lib_dir;
}
```

### Starting the BEAM

```rust
fn start_beam(app_module: &str) {
    // 1. Set environment variables
    let files_dir = FILES_DIR.lock().unwrap().clone();
    let otp_root = format!("{}/otp", files_dir);
    std::env::set_var("BINDIR", &format!("{}/{}/bin", otp_root, ERTS_VSN));
    std::env::set_var("ROOTDIR", &otp_root);
    // ... more env vars ...
    
    // 2. Symlink ERTS executables from nativeLibraryDir
    let native_lib_dir = NATIVE_LIB_DIR.lock().unwrap().clone();
    let exes = vec![
        ("erl_child_setup", "liberl_child_setup.so"),
        ("inet_gethost", "libinet_gethost.so"),
        ("epmd", "libepmd.so"),
    ];
    for (exe, lib) in exes {
        let bin_path = format!("{}/{}/bin/{}", otp_root, ERTS_VSN, exe);
        let lib_path = format!("{}/{}", native_lib_dir, lib);
        std::os::unix::fs::symlink(&lib_path, &bin_path).ok();
    }
    
    // 3. Wait for window focus (cold-start race condition fix)
    wait_for_window_focus();
    
    // 4. Build argv and call erl_start
    let mut args: Vec<CString> = /* ... build args ... */;
    unsafe {
        let mut argv: Vec<*mut c_char> = args.iter()
            .map(|s| s.as_ptr() as *mut c_char)
            .collect();
        erl_start(args.len() as c_int, argv.as_mut_ptr());
    }
}
```

---

## Erlang Distribution

Once the BEAM starts, it becomes an Erlang node reachable over the network.

### Node Naming

| Platform | Node Name Format | Example |
|----------|------------------|---------|
| iOS Simulator | `{app}_ios_{udid_short}@127.0.0.1` | `myapp_ios_a1b2c3d4@127.0.0.1` |
| iOS Device | `{app}_ios@{ip}` | `myapp_ios@192.168.1.100` |
| Android | `{app}_android_{serial}@127.0.0.1` | `myapp_android_abc123@127.0.0.1` |

### Connection Setup

```bash
# List connected devices
mix dala.devices

# Set up tunnels and connect
mix dala.connect

# Now you can connect from IEx
iex -S mix
node = :"myapp_ios@127.0.0.1"
Node.ping(node)  # => :pong
```

### Distribution Ports

- **EPMD**: 4369 (automatically started by Dala on device builds)
- **Inet dist**: Configurable via `-kernel inet_dist_listen_min/max`
- **Default**: 9101 (set via `DALA_DIST_PORT` env var)

---

## Troubleshooting

### BEAM Fails to Start

**Symptoms**: App stuck on "Starting BEAM..." splash screen.

**Check**:
1. **Crash dump**: Look in `Documents/dala_erl_crash.dump` (iOS) or `files/erl_crash.dump` (Android)
2. **Logs**: Check `beam_stdout.log` in the app's data directory
3. **OTP path**: Verify OTP is bundled correctly (device) or exists at `/tmp/otp-ios-sim` (simulator)

**Common causes**:
- OTP not bundled (device): Ensure `otp/` directory exists in the app bundle
- Memory limit (device): Check `-MIscs 10` flag is set
- Missing NIF: Ensure all NIFs are registered in `erts_static_nif_tab`

### Distribution Not Working

**Symptoms**: `mix dala.connect` fails, `Node.ping/1` returns `:pang`.

**Check**:
1. **EPMD running**: Device builds start EPMD in-process; check logs for "EPMD started"
2. **Port forwarding** (Android): `adb forward tcp:4369 tcp:4369`
3. **Firewall**: Ensure port 4369 and distribution port (9101) are open

### Hot Reload Not Working

**Symptoms**: `mix dala.push` succeeds but changes don't appear.

**Check**:
1. **Node connected**: Run `mix dala.connect` first
2. **Correct node name**: Use `mix dala.devices` to verify
3. **Module loaded**: On the device node, run `:code.is_loaded(MyModule)`

---

## Further Reading

- [iOS Physical Device Guide](ios_physical_device.md) — Detailed iOS device build process
- [Rustler in Mobile Guide](rustler_in_mob.md) — Writing NIFs for iOS/Android
- [Agentic Coding Guide](agentic_coding.md) — Using `Dala.Test` to drive the app
- [Render Engine Deep Dive](render_engine.md) — How UI trees reach the screen
- [Architecture Overview](architecture.md) — System design and deploy model
