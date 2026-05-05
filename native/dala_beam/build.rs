// build.rs - Handle conditional compilation flags for BEAM tuning
use std::env;

fn main() {
    // Pass through feature flags to C code that might be included
    if env::var("CARGO_FEATURE_BEAM_UNTUNED").is_ok() {
        println!("cargo:rustc-cfg=beam_untuned");
    }
    if env::var("CARGO_FEATURE_BEAM_SBWT_ONLY").is_ok() {
        println!("cargo:rustc-cfg=beam_sbwt_only");
    }
    if env::var("CARGO_FEATURE_BEAM_FULL_NERVES").is_ok() {
        println!("cargo:rustc-cfg=beam_full_nerves");
    }
    if env::var("CARGO_FEATURE_BEAM_USE_CUSTOM_FLAGS").is_ok() {
        println!("cargo:rustc-cfg=beam_use_custom_flags");
    }
    if env::var("CARGO_FEATURE_NO_BEAM").is_ok() {
        println!("cargo:rustc-cfg=no_beam");
    }
}
