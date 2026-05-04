#!/bin/bash
# Xcode build phase script - Add this as a "Run Script" phase in Xcode
# Ensure this runs BEFORE the compilation phase

set -e

# Get the project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR" ]; then
    # If BASH_SOURCE is not available, use SRCROOT
    SCRIPT_DIR="${SRCROOT}/ios"
fi

echo "=== Mob Rust Build Phase ==="
echo "Project dir: $SCRIPT_DIR"

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo "Error: Rust is not installed. Please install from https://rustup.rs"
    exit 1
fi

# Check if targets are installed
TARGETS=("aarch64-apple-ios" "aarch64-apple-ios-sim" "x86_64-apple-ios")
for target in "${TARGETS[@]}"; do
    if ! rustup target list --installed | grep -q "$target"; then
        echo "Installing target: $target"
        rustup target add "$target"
    fi
done

# Build Rust libraries
echo "Building Rust libraries..."
cd "$SCRIPT_DIR/rust"
./build_ios.sh

# Copy libraries to expected locations
echo "Copying libraries..."
mkdir -p "$SCRIPT_DIR/Frameworks"

# Copy device library (arm64)
if [ -f "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libmob_beam_ios.a" ]; then
    cp "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libmob_beam_ios.a" \
       "$SCRIPT_DIR/Frameworks/libmob_beam_ios_device.a"
    echo "✓ Copied device library"
fi

# Copy simulator libraries and create universal library
if [ -f "$SCRIPT_DIR/rust/target/aarch64-apple-ios-sim/release/libmob_beam_ios.a" ] && \
   [ -f "$SCRIPT_DIR/rust/target/x86_64-apple-ios/release/libmob_beam_ios.a" ]; then
    lipo -create \
        "$SCRIPT_DIR/rust/target/aarch64-apple-ios-sim/release/libmob_beam_ios.a" \
        "$SCRIPT_DIR/rust/target/x86_64-apple-ios/release/libmob_beam_ios.a" \
        -output "$SCRIPT_DIR/Frameworks/libmob_beam_ios_simulator.a"
    echo "✓ Created universal simulator library"
fi

# Copy driver table library
if [ -f "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libdriver_tab_ios.a" ]; then
    cp "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libdriver_tab_ios.a" \
       "$SCRIPT_DIR/Frameworks/libdriver_tab_ios_device.a"
    echo "✓ Copied driver table device library"
fi

echo "=== Rust build complete ==="
echo "Libraries are in: $SCRIPT_DIR/Frameworks/"
