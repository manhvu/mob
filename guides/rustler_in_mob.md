# Rustler in Mob - Guide for Developers

## Overview

Mob uses [Rustler](https://github.com/ruster/rustler) to create NIFs (Native Implemented Functions) that bridge Elixir with native code written in Rust. This guide explains how to extend Mob with your own Rust code.

## When to Use Rustler in Mob

Use Rustler when you need to:
- Call platform-specific native APIs (iOS/Android) from Elixir
- Perform CPU-intensive operations that benefit from Rust's performance
- Integrate existing Rust libraries into your Mob app
- Create custom native components that aren't covered by Mob's built-in NIF

## Project Structure

Mob's Rust code lives in:
- `mob/native/mob_nif/` - Main NIF library (Rustler-based)
- `mob/ios/rust/` - iOS-specific Rust code
- `mob/android/jni/rust/` - Android-specific Rust code

## Creating a New NIF Function

### 1. Add the Rust function

Edit `mob/native/mob_nif/src/lib.rs`:

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
    "Elixir.Mob.Native",
    [
        // ... existing functions ...
        my_custom_function,
    ]
);
```

### 2. Add the Elixir wrapper

Edit `mob/lib/mob/native.ex`:

```elixir
defmodule Mob.Native do
  # ... existing functions ...
  
  @doc "My custom function"
  def my_custom_function(_input), do: :erlang.nif_error(:nif_not_loaded)
end
```

### 3. Build the Rust library

**iOS:**
```bash
cd mob/ios/rust
cargo build --release --target aarch64-apple-ios
cargo build --release --target x86_64-apple-ios  # for simulator
```

**Android:**
```bash
cd mob/android/jni/rust
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

Mob uses FFI (Foreign Function Interface) to call into iOS frameworks:

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
    let class = env.find_class("com/example/mob/MobBridge").unwrap();
    let method = env.get_static_method_id(class, "someMethod", "()V").unwrap();
    // Call the method...
}
```

## Testing Your NIF

1. **Unit tests in Rust:**
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

2. **Integration tests from Elixir:**
   ```elixir
   test "my custom function works" do
     assert {:ok, result} = Mob.Native.my_custom_function("test")
   end
   ```

## Common Patterns in Mob

### Message Delivery from Native to Elixir

To send messages from native code to Elixir processes:

```rust
#[no_mangle]
pub extern "C" fn deliver_to_elixir(json_utf8: *const std::ffi::c_char) {
    unsafe {
        // Convert C string to Rust string
        let cstr = std::ffi::CStr::from_ptr(json_utf8);
        let json = cstr.to_str().unwrap();
        
        // Use cached environment to send message
        // (Implementation depends on your message passing design)
    }
}
```

### Caching Environment for Callbacks

Mob caches the Erlang environment for use by ObjC callbacks:

```rust
lazy_static::lazy_static! {
    static ref CACHED_ENV: Mutex<Option<*mut std::ffi::c_void>> = Mutex::new(None);
}

#[rustler::nif]
fn cache_env<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let env_ptr = env.as_c_arg() as *mut std::ffi::c_void;
    let mut cached = CACHED_ENV.lock().unwrap();
    *cached = Some(env_ptr);
    ok(env)
}
```

## Debugging Tips

1. **Use logging:**
   - Rust: `eprintln!("Debug: {}", value);` (shows in logcat on Android, stderr on iOS)
   - iOS: Use `NSLog` via FFI
   - Elixir: Use `:mob_nif.log/1` for early startup, `Logger` after `Mob.App.start`

2. **Check NIF loading:**
   ```elixir
   :code.is_loaded(Mob.Native)
   ```

3. **Test NIF functions directly:**
   ```elixir
   :mob_nif.my_custom_function("test")
   ```

## Best Practices

1. **Error handling:** Always return proper NIF errors
2. **Memory safety:** Use Rust's ownership system, avoid unsafe when possible
3. **Platform checks:** Use `#[cfg()]` attributes for platform-specific code
4. **Documentation:** Document your NIF functions in both Rust and Elixir
5. **Testing:** Write tests for both Rust and Elixir sides

## Examples from Mob's Codebase

- `mob/native/mob_nif/src/lib.rs` - Main NIF entry point
- `mob/native/mob_nif/src/ios.rs` - iOS-specific implementations
- `mob/native/mob_nif/src/android.rs` - Android-specific implementations
- `mob/native/mob_nif/src/common.rs` - Shared code and platform dispatch

## Further Reading

- [Rustler Documentation](https://docs.rs/rustler)
- [Rust FFI Guide](https://doc.rust-lang.org/nomicon/ffi.html)
- [JNI Documentation](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/)
- [Objective-C Runtime](https://developer.apple.com/documentation/objectivec/objective-c_runtime)
