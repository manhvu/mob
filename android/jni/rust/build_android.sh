#!/bin/bash
# build_android.sh - Build Rust libraries for Android
# This script builds the Rust code for Android targets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$SCRIPT_DIR"

# Android targets
TARGETS=(
    "aarch64-linux-android"    # ARM64
    "armv7-linux-androideabi"  # ARM32
    "x86_64-linux-android"     # x86_64 simulator
    "i686-linux-android"       # x86 simulator
)

# Android NDK path - adjust this to your NDK location
ANDROID_NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME}/ndk/27.0.12077973}"

if [ ! -d "$ANDROID_NDK" ]; then
    echo "Error: Android NDK not found at $ANDROID_NDK"
    echo "Set ANDROID_NDK_HOME or ANDROID_HOME environment variable"
    exit 1
fi

echo "Using Android NDK: $ANDROID_NDK"

# Detect host OS for NDK prebuilt path
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    darwin)
        NDK_HOST="darwin-x86_64"
        ;;
    linux)
        NDK_HOST="linux-x86_64"
        ;;
    *)
        echo "Error: Unsupported host OS: $(uname -s)"
        exit 1
        ;;
esac

echo "Detected host: $NDK_HOST"

# Install targets if not present
for target in "${TARGETS[@]}"; do
    if ! rustup target list --installed | grep -q "$target"; then
        echo "Installing target: $target"
        rustup target add "$target"
    fi
done

# Parse feature flags
FEATURES=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --features)
            FEATURES="$2"
            shift 2
            ;;
        --release)
            RELEASE="--release"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Build for each target
for target in "${TARGETS[@]}"; do
    echo "Building for $target..."

    # Set up cargo config for this target
    # Convert target name to uppercase with underscores for env var
    TARGET_UPPER=$(echo "$target" | tr '[:lower:]-' '[:upper:]_')
    TARGET_LINKER="${ANDROID_NDK}/toolchains/llvm/prebuilt/${NDK_HOST}/bin/${target}-clang"

    export "CARGO_TARGET_${TARGET_UPPER}_LINKER=$TARGET_LINKER"

    # Build
    cd "$RUST_DIR"
    if [ -n "$FEATURES" ]; then
        cargo build --target "$target" --release --features "$FEATURES"
    else
        cargo build --target "$target" --release
    fi

    echo "Built: $RUST_DIR/target/$target/release/libdala_beam.so"
done

echo ""
echo "Android build complete!"
echo "Libraries are in: $RUST_DIR/target/*/release/"
echo ""
echo "To build with specific features:"
echo "  ./build_android.sh --features no_beam"
echo "  ./build_android.sh --features beam_untuned"
