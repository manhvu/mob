// driver_tab_ios.rs - Static NIF table with dala_nif added for iOS
// Converted from driver_tab_ios.c
// Link BEFORE libbeam.a to override the built-in driver_tab.
// Mirrors driver_tab_android.rs for iOS.

use std::ffi::c_void;
use std::os::raw::{c_int, c_ulong};

// ErtsStaticDriver struct
#[repr(C)]
pub struct ErtsStaticDriver {
    pub de: *mut c_void,
    pub flags: c_int,
}

// ErtsStaticNif struct
#[repr(C)]
pub struct ErtsStaticNif {
    pub nif_init: Option<unsafe extern "C" fn() -> *mut c_void>,
    pub is_builtin: c_int,
    pub nif_mod: c_ulong,
    pub entry: *mut c_void,
}

const THE_NON_VALUE: c_ulong = c_ulong::MAX;

// External driver entries (from ERTS)
extern "C" {
    pub static mut inet_driver_entry: c_void;
    pub static mut ram_file_driver_entry: c_void;
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
    // exqlite sqlite3_nif is linked statically on device (conditionally)
    #[cfg(feature = "dala_static_sqlite_nif")]
    pub fn sqlite3_nif_nif_init() -> *mut c_void;
}

// Driver table
#[no_mangle]
pub static mut driver_tab: [ErtsStaticDriver; 3] = [
    ErtsStaticDriver {
        de: unsafe { &mut inet_driver_entry },
        flags: 0,
    },
    ErtsStaticDriver {
        de: unsafe { &mut ram_file_driver_entry },
        flags: 0,
    },
    ErtsStaticDriver {
        de: std::ptr::null_mut(),
        flags: 0,
    },
];

// Stub function for erts_init_static_drivers
#[no_mangle]
pub extern "C" fn erts_init_static_drivers() {
    // No-op for static linking
}

// Static NIF table - size depends on whether sqlite3_nif is included
#[cfg(not(feature = "dala_static_sqlite_nif"))]
#[no_mangle]
pub static mut erts_static_nif_tab: [ErtsStaticNif; 11] = [
    ErtsStaticNif {
        nif_init: Some(prim_tty_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(erl_tracer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_buffer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_file_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zlib_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zstd_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_socket_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_net_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(asn1rt_nif_nif_init),
        is_builtin: 1,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(dala_nif_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: None,
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
];

#[cfg(feature = "dala_static_sqlite_nif")]
#[no_mangle]
pub static mut erts_static_nif_tab: [ErtsStaticNif; 12] = [
    ErtsStaticNif {
        nif_init: Some(prim_tty_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(erl_tracer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_buffer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_file_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zlib_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(zstd_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_socket_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(prim_net_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(asn1rt_nif_nif_init),
        is_builtin: 1,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: Some(dala_nif_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // sqlite3_nif included when dala_static_sqlite_nif feature is enabled
    ErtsStaticNif {
        nif_init: Some(sqlite3_nif_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    ErtsStaticNif {
        nif_init: None,
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
];
