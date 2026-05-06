// driver_tab.rs - Static driver and NIF tables for Android
// This file defines the driver_tab and erts_static_nif_tab that ERTS uses
// to find built-in drivers and NIFs at startup.
// Link BEFORE libbeam.a to override the built-in tables.

use std::ffi::c_void;
use std::os::raw::{c_int, c_ulong};

// ── ERTS Struct Definitions ──────────────────────────────────────────────

/// Driver entry for ERTS static driver table.
/// Must match the layout of ErtsStaticDriver in ERTS.
#[repr(C)]
pub struct ErtsStaticDriver {
    /// Pointer to driver entry structure
    pub de: *mut c_void,
    /// Driver flags
    pub flags: c_int,
}

/// NIF entry for ERTS static NIF table.
/// Must match the layout of ErtsStaticNif in ERTS.
#[repr(C)]
pub struct ErtsStaticNif {
    /// NIF initialization function
    pub nif_init: Option<extern "C" fn() -> *mut c_void>,
    /// Is this a built-in NIF?
    pub is_builtin: c_int,
    /// Module atom (THE_NON_VALUE for dynamic loading)
    pub nif_mod: c_ulong,
    /// Entry pointer (unused for static NIFs)
    pub entry: *mut c_void,
}

// THE_NON_VALUE is used to indicate "no module atom yet"
const THE_NON_VALUE: c_ulong = c_ulong::MAX;

// ── External Driver Entries (from ERTS) ───────────────────────────────────

extern "C" {
    /// TCP/UDP socket driver
    pub static mut inet_driver_entry: c_void;
    /// RAM file driver
    pub static mut ram_file_driver_entry: c_void;
}

// ── External NIF Init Functions (from ERTS) ───────────────────────────────

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
}

// ── External NIF from dala_nif ────────────────────────────────────────────

extern "C" {
    /// Dala's NIF initialization function (defined in dala_nif crate)
    pub fn dala_nif_nif_init() -> *mut c_void;
}

// ── Static Driver Table ───────────────────────────────────────────────────

/// Static driver table for ERTS.
/// Contains the drivers that are always available.
/// The table is terminated by a null entry.
#[no_mangle]
pub static mut driver_tab: [ErtsStaticDriver; 3] = [
    // TCP/UDP socket driver
    ErtsStaticDriver {
        de: unsafe { &mut inet_driver_entry as *mut c_void as *mut _ },
        flags: 0,
    },
    // RAM file driver
    ErtsStaticDriver {
        de: unsafe { &mut ram_file_driver_entry as *mut c_void as *mut _ },
        flags: 0,
    },
    // Terminator
    ErtsStaticDriver {
        de: std::ptr::null_mut(),
        flags: 0,
    },
];

/// Initialize static drivers.
/// Called by ERTS during startup.
#[no_mangle]
pub extern "C" fn erts_init_static_drivers() {
    // No-op for static linking - drivers are already in the table
}

// ── Static NIF Table ──────────────────────────────────────────────────────

/// Static NIF table for ERTS.
/// Contains the NIFs that are always available.
/// The table is terminated by a null entry.
#[no_mangle]
pub static mut erts_static_nif_tab: [ErtsStaticNif; 11] = [
    // prim_tty - terminal I/O
    ErtsStaticNif {
        nif_init: Some(prim_tty_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // erl_tracer - tracing support
    ErtsStaticNif {
        nif_init: Some(erl_tracer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // prim_buffer - binary buffers
    ErtsStaticNif {
        nif_init: Some(prim_buffer_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // prim_file - file I/O
    ErtsStaticNif {
        nif_init: Some(prim_file_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // zlib - compression
    ErtsStaticNif {
        nif_init: Some(zlib_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // zstd - Zstandard compression
    ErtsStaticNif {
        nif_init: Some(zstd_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // prim_socket - socket NIF
    ErtsStaticNif {
        nif_init: Some(prim_socket_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // prim_net - network NIF
    ErtsStaticNif {
        nif_init: Some(prim_net_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // asn1rt_nif - ASN.1 runtime (built-in)
    ErtsStaticNif {
        nif_init: Some(asn1rt_nif_nif_init),
        is_builtin: 1,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // dala_nif - Dala's UI NIF
    ErtsStaticNif {
        nif_init: Some(dala_nif_nif_init),
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
    // Terminator
    ErtsStaticNif {
        nif_init: None,
        is_builtin: 0,
        nif_mod: THE_NON_VALUE,
        entry: std::ptr::null_mut(),
    },
];
