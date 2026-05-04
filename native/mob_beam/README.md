# mob_beam - Rust Conversion of C BEAM Launcher

## Overview

This crate is a Rust conversion of the C files `mob_beam.c` and `driver_tab_*.c` from the mob repository. It provides:

1. **BEAM runtime launcher** for Android (converted from `mob_beam.c`)
2. **Static NIF/driver tables** for linking (converted from `driver_tab_android.c` and `driver_tab_ios.c`)

## Files Converted

### From C to Rust:

| Original C File | Rust File | Description |
|----------------|-----------|-------------|
| `android/jni/mob_beam.c` | `src/lib.rs` | BEAM launcher, JNI bridge init, event senders |
| `android/jni/mob_beam.h` | `src/header.rs` | Public API declarations |
| `android/jni/driver_tab_android.c` | `src/driver_tab_android.rs` | Android static NIF table |
| `ios/driver_tab_ios.c` | `src/driver_tab_ios.rs` | iOS static NIF table |

## Features

The crate supports conditional compilation via features:

- `no_beam` - Skip BEAM launch (for battery baseline testing)
- `beam_untuned` - No BEAM tuning flags
- `beam_sbwt_only` - Only SBWT tuning
- `beam_full_nerves` - Full Nerves-style tuning (default)
- `beam_use_custom_flags` - Use custom flags from `mob_beam_flags.h`
- `mob_static_sqlite_nif` - Statically link sqlite3 NIF (iOS device only)

## Usage

This crate is linked statically with the BEAM runtime. The static tables (`driver_tab` and `erts_static_nif_tab`) are exported with `#[no_mangle]` to match the C expected symbols.

### For Android:

```toml
[dependencies]
mob_beam = { path = "../mob_beam" }
```

### For iOS:

```toml
[dependencies]
mob_beam = { path = "../mob_beam", features = ["mob_static_sqlite_nif"] }
```

## Implementation Status

### Completed:
- ✅ Static NIF tables (Android & iOS)
- ✅ Basic JNI function stubs
- ✅ BEAM startup logic structure
- ✅ Environment variable setup
- ✅ Feature flag system

### Stubs (need implementation):
- ⚠️ `mob_send_*` event functions
- ⚠️ JNI bridge cache functions
- ⚠️ Cold-start race condition fix (window focus polling)
- ⚠️ `erl_start` FFI call
- ⚠️ SQLite3 NIF symlink logic

## Building

```bash
# Android
cargo build -p mob_beam --target aarch64-linux-android

# iOS
cargo build -p mob_beam --target aarch64-apple-ios

# iOS Simulator
cargo build -p mob_beam --target x86_64-apple-ios
```

## Notes

- The `mob_nif` crate (separate) handles the actual NIF implementations using Rustler
- This crate (`mob_beam`) handles BEAM startup and JNI bridge initialization
- The static tables reference `mob_nif_nif_init` which is exported by the `mob_nif` crate
