#!/bin/bash
# build_android.sh - Build Rust libraries for Android
# This script builds the Rust code for Android targets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$SCRIPT_DIR/rust"

# Android targets
TARGETS=(
    "aarch64-linux-android"    # ARM64
    "armv7-linux-androideabi"  # ARM32
    "x86_64-linux-android"     # x86_64 simulator
    "i686-linux-android"       # x86 simulator
)

# Android NDK path - adjust this to your NDK location
ANDROID_NDK="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk-bundle}"

if [ ! -d "$ANDROID_NDK" ]; then
    echo "Error: Android NDK not found at $ANDROID_NDK"
    echo "Set ANDROID_NDK_HOME or ANDROID_HOME environment variable"
    exit 1
fi

echo "Using Android NDK: $ANDROID_NDK"

# Install targets if not present
for target in "${TARGETS[@]}"; do
    if ! rustup target list --installed | grep -q "$target"; then
        echo "Installing target: $target"
        rustup target add "$target"
    fi
done

# Build for each target
for target in "${TARGETS[@]}"; do
    echo "Building for $target..."

    # Set up cargo config for this target
    export CARGO_TARGET_${target^^}_LINKER="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${target}-clang"

    # Build
    cd "$RUST_DIR"
    cargo build --target "$target" --release

    echo "Built: $RUST_DIR/target/$target/release/libmob_beam.so"
done

echo "Android build complete!"
echo "Libraries are in: $RUST_DIR/target/*/release/"
