// driver_tab_ios.rs — Static NIF table with dala_nif added.
// Link BEFORE libbeam.a to override the built-in driver_tab.
// Mirrors driver_tab_android.rs for iOS.

use std::ffi::c_void;
use std::ptr;

// Opaque types for driver entries
#[repr(C)]
pub struct ErlDrvEntryStub {
    pub de: *mut c_void,
    pub flags: i32,
}

#[repr(C)]
pub struct ErtsStaticDriver {
    pub de: *mut c_void,
    pub flags: i32,
}

#[repr(C)]
pub struct ErtsStaticNif {
    pub nif_init: Option<unsafe extern "C" fn() -> *mut c_void>,
    pub is_builtin: i32,
    pub nif_mod: u64,
    pub entry: *mut c_void,
}

// External driver entries from Erlang runtime
extern "C" {
    pub static mut inet_driver_entry: ErlDrvEntryStub;
    pub static mut ram_file_driver_entry: ErlDrvEntryStub;
}

// External NIF init functions
extern "C" {
    pub fn prim_tty_nif_init() -> *mut c_void;
    pub fn erl_tracer_nif_init() -> *mut c_void;
    pub fn prim_buffer_nif_init() -> *mut c_void;
    pub fn prim_file_nif_init() -> *mut c_void;
    pub fn zlib_nif_init() -> *mut c_void;
    pub fn zstd_nif_init() -> *mut c_void;
    pub fn prim_socket_nif_init() -> *mut c_void;
    pub fn prim_net_nif_init() -> *mut c_void;
    pub fn asn1rt_nif_nif_init() -> *mut c_void;
    pub fn dala_nif_nif_init() -> *mut c_void;
    // exqlite sqlite3_nif is linked statically on device (pass -DDALA_STATIC_SQLITE_NIF
    // when compiling this file in device builds). On simulator it loads dynamically
    // as a .so and must NOT appear in the static table.
}

const THE_NON_VALUE: u64 = 0u64;

#[no_mangle]
pub static mut driver_tab: [ErtsStaticDriver; 3] = [
    ErtsStaticDriver {
        de: unsafe { &mut inet_driver_entry as *mut _ as *mut c_void },
        flags: 0,
    },
    ErtsStaticDriver {
        de: unsafe { &mut ram_file_driver_entry as *mut _ as *mut c_void },
        flags: 0,
    },
    ErtsStaticDriver {
        de: ptr::null_mut(),
        flags: 0,
    },
];

#[no_mangle]
pub extern "C" fn erts_init_static_drivers() {
    // No-op, mirrors C version
}

// Base table without sqlite3_nif (for simulator builds)
#[no_mangle]
pub static mut erts_static_nif_tab: [ErtsStaticNif; 11] = [
    ErtsStaticNif {
        nif_init: Some(prim_tty_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(erl_tracer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_buffer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_file_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zlib_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zstd_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_socket_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_net_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(asn1rt_nif_nif_init),
        is_builtin: 1,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(dala_nif_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: None,
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
];

// For device builds with DALA_STATIC_SQLITE_NIF, use this alternative table
// that includes sqlite3_nif_nif_init.
#[cfg(feature = "static_sqlite_nif")]
#[no_mangle]
pub static mut erts_static_nif_tab_device: [ErtsStaticNif; 12] = [
    ErtsStaticNif {
        nif_init: Some(prim_tty_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(erl_tracer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_buffer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_file_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zlib_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zstd_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_socket_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_net_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(asn1rt_nif_nif_init),
        is_builtin: 1,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(dala_nif_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(sqlite3_nif_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: None,
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: ptr::null_mut(),
    },
];

#[cfg(feature = "static_sqlite_nif")]
extern "C" {
    pub fn sqlite3_nif_nif_init() -> *mut c_void;
}
