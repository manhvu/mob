# Rustler in Dala - Complete Guide

## Overview

Dala uses [Rustler](https://github.com/ruster/rustler) to create NIFs (Native Implemented Functions) that bridge Elixir with native code written in Rust. This guide explains how to extend Dala with your own Rust code, handle platform-specific dispatch, and implement message sending.

> **Architecture note:** Dala's NIF does not cache `Env` across calls (unsafe). `cache_env/1` is a stub kept for API compatibility. Message sending from ObjC/Java callbacks uses platform-specific dispatch, not cached env.

## When to Use Rustler in Dala

Use Rustler when you need to:
- Call platform-specific native APIs (iOS/Android) from Elixir
- Perform CPU-intensive operations that benefit from Rust's performance
- Integrate existing Rust libraries into your Dala app
- Create custom native components not covered by Dala's built-in NIF

## Project Structure

Dala's Rust code lives in:
- `dala/native/dala_nif/` - Main NIF library (Rustler-based)
- `dala/native/dala_nif/src/ios.rs` - iOS-specific (ObjC messaging)
- `dala/native/dala_nif/src/android.rs` - Android-specific (JNI)
- `dala/native/dala_nif/src/common.rs` - Shared code and platform dispatch

## Creating a New NIF Function

### 1. Add the Rust function

Edit `dala/native/dala_nif/src/lib.rs`:

```rust
use rustler::{Env, NifResult, Term};

#[rustler::nif]
fn my_custom_function<'a>(env: Env<'a>, input: Term<'a>) -> NifResult<Term<'a>> {
    // Your Rust implementation here
    let input_str: String = input.decode()?;
    let result = format!("Processed: {}", input_str);
    
    // Return the result
    Ok(rustler::types::binary::Binary::from_bytes(result.as_bytes())
        .to_term(env)
        .unwrap())
}

// Register the function in the rustler::init! macro at the bottom of the file:
rustler::init!(
    "Elixir.Dala.Native",
    [
        // ... existing functions ...
        my_custom_function,
    ]
);
```

### 2. Add the Elixir wrapper

Edit `dala/lib/dala/native.ex`:

```elixir
defmodule Dala.Native do
  # ... existing functions ...
  
  @doc "My custom function"
  def my_custom_function(_input), do: :erlang.nif_error(:nif_not_loaded)
end
```

### 3. Build the Rust library

**iOS:**
```bash
cd dala/ios/rust
cargo build --release --target aarch64-apple-ios
cargo build --release --target x86_64-apple-ios  # for simulator
```

**Android:**
```bash
cd dala/android/jni/rust
cargo build --release --target aarch64-linux-android
cargo build --release --target armv7-linux-androideabi
```

## Platform-Specific Code

Use conditional compilation to handle platform differences:

```rust
#[cfg(target_os = "ios")]
mod ios {
    pub fn platform_specific() -> &'static str {
        "Running on iOS"
    }
}

#[cfg(target_os = "android")]
mod android {
    pub fn platform_specific() -> &'static str {
        "Running on Android"
    }
}

pub fn get_platform_info() -> String {
    #[cfg(target_os = "ios")]
    return ios::platform_specific().to_string();
    
    #[cfg(target_os = "android")]
    return android::platform_specific().to_string();
    
    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    return "Unknown platform".to_string();
}
```

## Calling Objective-C/Swift from Rust (iOS)

Dala uses FFI (Foreign Function Interface) to call into iOS frameworks:

```rust
use objc::runtime::{Class, Object};
use objc::{class, msg_send};

pub fn ios_specific_task() {
    unsafe {
        let cls: *mut Object = msg_send![class!(SomeiOSClass), sharedInstance];
        if !cls.is_null() {
            let _: () = msg_send![cls, someMethod];
        }
    }
}
```

## Calling Java from Rust (Android)

Use JNI (Java Native Interface) to call Android APIs:

```rust
use jni::objects::{JClass, JString};
use jni::JNIEnv;

pub fn android_specific_task(env: &mut JNIEnv) {
    let class = env.find_class("com/example/dala/dalaBridge").unwrap();
    let method = env.get_static_method_id(class, "someMethod", "()V").unwrap();
    // Call the method...
}
```

## Message Delivery from Native to Elixir

### The Challenge

Functions like `dala_deliver_webview_eval_result` are:
1. Called from ObjC (iOS) or Java (Android) callbacks
2. Need to send messages to Erlang processes (e.g., `:dala_screen`)
3. Don't have direct access to `Env` from the NIF context

### Current Approach: Platform-Specific Dispatch

Dala uses platform-specific dispatch rather than cached `Env`:

- **iOS**: ObjC message passing via `msg_send!`
- **Android**: JNI calls via `jni` crate
- **No caching**: `cache_env/1` is a no-op stub for API compatibility

### Current Status (as of dala 0.0.x):

- ✅ `cache_env` stub exists for API compatibility
- ✅ `dala_deliver_webview_eval_result` logs results via `eprintln!`
- ❌ Direct message sending from callbacks not yet implemented

For now, use `eprintln!` for debugging from native callbacks.

### The Proper Way: Use Erlang C API

The correct way to send messages from C code (which Rust can call) is to use Erlang's C API:

```c
#include <erl_nif.h>

// Get process ID by name
ErlNifPid* pid = enif_whereis(env, "dala_screen");

// Send a tuple message
ErlNifTerm* message = enif_make_tuple(env, 3,
    enif_make_atom(env, "webview"),
    enif_make_atom(env, "eval_result"),
    enif_make_binary(env, json, strlen(json))
);

enif_send(env, pid, message, 0);
```

### Recommended Implementation Steps

1. **For now (stub)**: Log the result using `eprintln!`
2. **Short term**: Implement using Erlang C API FFI
3. **Long term**: Create proper Rust bindings for Erlang C API

## Environment Handling

Dala's NIF does **not** cache `Env` across NIF calls (unsafe, lifetime issues). `cache_env/1` is a no-op stub kept for API compatibility:

```rust
// lib.rs
#[rustler::nif]
fn cache_env<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    // Env cannot be safely cached - lifetime tied to NIF call
    // This stub exists for API compatibility
    ok(env)
}
```

Message sending from ObjC/Java callbacks uses platform-specific dispatch, not a cached environment.

## Testing Your NIF

### 1. Unit tests in Rust:

```rust
#[cfg(test)]
mod tests {
    use super::*;
       
    #[test]
    fn test_my_function() {
        // Test your Rust code
    }
}
```

### 2. Integration tests from Elixir:

```elixir
test "my custom function works" do
  assert {:ok, result} = Dala.Native.my_custom_function("test")
end
```

## Debugging Tips

1. **Use logging:**
   - Rust: `eprintln!("Debug: {}", value);` (shows in logcat on Android, stderr on iOS)
   - iOS: Use `NSLog` via FFI
   - Elixir: Use `:dala_nif.log/1` for early startup, `Logger` after `Dala.App.start`

2. **Check NIF loading:**
   ```elixir
   :code.is_loaded(Dala.Native)
   ```

3. **Test NIF functions directly:**
   ```elixir
   :dala_nif.my_custom_function("test")
   ```

## Best Practices

1. **Error handling:** Always return proper NIF errors
2. **Memory safety:** Use Rust's ownership system, avoid unsafe when possible
3. **Platform checks:** Use `#[cfg()]` attributes for platform-specific code
4. **Documentation:** Document your NIF functions in both Rust and Elixir
5. **Testing:** Write tests for both Rust and Elixir sides

## Examples from Dala's Codebase

- `dala/native/dala_nif/src/lib.rs` - Main NIF entry point
- `dala/native/dala_nif/src/ios.rs` - iOS-specific implementations
- `dala/native/dala_nif/src/android.rs` - Android-specific implementations
- `dala/native/dala_nif/src/common.rs` - Shared code and platform dispatch

## Further Reading

- [Rustler Documentation](https://docs.rs/rustler)
- [Rust FFI Guide](https://doc.rust-lang.org/nomicon/ffi.html)
- [JNI Documentation](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/)
- [Objective-C Runtime](https://developer.apple.com/documentation/objectivec/objective-c_runtime)
- [Erlang NIF C API](http://erlang.org/doc/man/erl_nif.html)
