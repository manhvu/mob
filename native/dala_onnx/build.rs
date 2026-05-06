// build.rs - Handle ONNX Runtime linking for different platforms.

fn main() {
    // Check which platform we're building for
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    match target_os.as_str() {
        "ios" => {
            // iOS: Link against ONNX Runtime static library
            // The library should be at: ../onnxruntime-ios/lib/
            if std::path::Path::new("../onnxruntime-ios/lib").exists() {
                println!("cargo:rustc-link-search=native=../onnxruntime-ios/lib");
                println!("cargo:rustc-link-lib=static=onnxruntime");
            } else {
                println!("cargo:warning=ONNX Runtime iOS lib not found. Skipping linking.");
            }
        }
        "android" => {
            // Android: Link against ONNX Runtime shared library
            // The library should be at: ../onnxruntime-android/jni/arm64-v8a/
            if std::path::Path::new("../onnxruntime-android/jni/arm64-v8a").exists() {
                println!("cargo:rustc-link-search=native=../onnxruntime-android/jni/arm64-v8a");
                println!("cargo:rustc-link-lib=onnxruntime");
            } else {
                println!("cargo:warning=ONNX Runtime Android lib not found. Skipping linking.");
            }
        }
        "macos" => {
            // macOS (for testing): Link against ONNX Runtime
            if std::path::Path::new("../onnxruntime-macos/lib").exists() {
                println!("cargo:rustc-link-search=native=../onnxruntime-macos/lib");
                println!("cargo:rustc-link-lib=onnxruntime");
            } else {
                println!("cargo:warning=ONNX Runtime macOS lib not found. Skipping linking.");
            }
        }
        _ => {
            // Linux/Windows: default handling
            println!("cargo:warning=Unknown target OS: {}", target_os);
        }
    }

    // Tell cargo to re-run this script if target OS changes
    println!("cargo:rerun-if-env-changed=CARGO_CFG_TARGET_OS");
}
