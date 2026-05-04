# Implementing Proper Message Sending in Rustler

## Overview

This document explains how to properly implement message sending from Rust NIFs to Erlang processes. This is needed for `mob_deliver_webview_eval_result` and similar functions that are called from ObjC/Java callbacks.

## The Challenge

Functions like `mob_deliver_webview_eval_result` are:
1. Called from ObjC (iOS) or Java (Android) callbacks
2. Need to send messages to Erlang processes (e.g., `:mob_screen`)
3. Don't have direct access to `Env` from the NIF context

## Solution: Use Cached Environment

### 1. Cache the Environment

In `lib.rs`, cache the Erlang environment during NIF initialization:

```rust
use std::sync::Mutex;
use rustler::Env;

lazy_static::lazy_static! {
    static ref CACHED_ENV: Mutex<Option<usize>> = Mutex::new(None);
}

#[rustler::nif]
fn cache_env<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let env_ptr = env.as_c_arg() as usize;
    let mut cached = CACHED_ENV.lock().unwrap();
    *cached = Some(env_ptr);
    ok(env)
}
```

Register `cache_env` in `rustler::init!` macro.

### 2. Reconstruct Env from Cached Pointer

In `mob_deliver_webview_eval_result`:

```rust
#[no_mangle]
pub extern "C" fn mob_deliver_webview_eval_result(json_utf8: *const std::ffi::c_char) {
    unsafe {
        if json_utf8.is_null() { return; }
        
        let json = {
            let cstr = std::ffi::CStr::from_ptr(json_utf8);
            match cstr.to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return,
            }
        };
        
        let cached = CACHED_ENV.lock().unwrap();
        if let Some(env_ptr) = *cached {
            // Reconstruct Env from cached pointer
            // NOTE: This is unsafe and may not work correctly
            // The proper way is to use Erlang's C API
            let env = Env::new(
                std::mem::transmute::<usize, *mut rustler::wrapper::env::c_erl_nif_env>(env_ptr)
            );
            
            // Send message to :mob_screen process
            // This requires proper process lookup
            eprintln!("[Mob] WebView eval result: {}", json);
        }
    }
}
```

## The Proper Way: Use Erlang C API

The correct way to send messages from C code (which Rust can call) is to use Erlang's C API:

### Erlang C API Functions

```c
#include <erl_nif.h>

// Get process ID by name
ErlNifPid* pid = enif_whereis(env, "mob_screen");

// Send a tuple message
ErlNifTerm* message = enif_make_tuple(env, 3,
    enif_make_atom(env, "webview"),
    enif_make_atom(env, "eval_result"),
    enif_make_binary(env, json, strlen(json))
);

enif_send(env, pid, message, 0);
```

### Rust FFI to Erlang C API

Create Rust bindings to Erlang C API:

```rust
use std::os::raw::c_char;

extern "C" {
    fn enif_whereis(env: *mut c_void, name: *const c_char) -> *mut c_void;
    fn enif_send(env: *mut c_void, to: *mut c_void, msg: *mut c_void, flags: c_int) -> c_int;
    // ... other functions
}

pub fn send_to_mob_screen(json: &str) {
    unsafe {
        let env = ...; // Get cached env
        let pid = enif_whereis(env, "mob_screen\0".as_ptr() as *const c_char);
        if !pid.is_null() {
            // Create and send message
        }
    }
}
```

## Alternative: Use Rustler's encode/decode

Rustler provides functions to encode/decode Erlang terms:

```rust
use rustler::types::{atom, binary, tuple};

fn send_message(env: &Env, pid: rustler::types::pid::Pid, json: &str) {
    let webview_atom = atom::Atom::from_str(env, "webview")
        .unwrap()
        .to_term(env)
        .unwrap();
    let eval_result_atom = atom::Atom::from_str(env, "eval_result")
        .unwrap()
        .to_term(env)
        .unwrap();
    let json_term = binary::Binary::from_bytes(json.as_bytes())
        .to_term(env)
        .unwrap();
    
    let message = tuple::make_tuple(env, &[webview_atom, eval_result_atom, json_term]);
    
    // Send using env.send or similar
}
```

## Recommended Implementation Steps

1. **For now (stub)**: Log the result using `eprintln!`
2. **Short term**: Implement using Erlang C API FFI
3. **Long term**: Create proper Rust bindings for Erlang C API

## Current Status in Mob

- ✅ `CACHED_ENV` is implemented
- ✅ `cache_env` NIF is implemented
- ✅ `mob_deliver_webview_eval_result` logs results
- ❌ Message sending is not implemented (stub)

## Next Steps

1. Create FFI bindings to Erlang C API (`enif_whereis`, `enif_send`, etc.)
2. Implement `send_to_process(pid, term)` function
3. Update `mob_deliver_webview_eval_result` to actually send messages
4. Test with a running Mob app

## References

- [Rustler Documentation](https://docs.rs/rustler)
- [Erlang NIF C API](http://erlang.org/doc/man/erl_nif.html)
- [Rust FFI Guide](https://doc.rust-lang.org/nomicon/ffi.html)
