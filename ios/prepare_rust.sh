#!/bin/bash
# prepare_rust.sh - Prepare Rust libraries for iOS build
# This should be run before building the Xcode project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Building Rust libraries for iOS ==="

# Build Rust libraries
cd "$SCRIPT_DIR/rust"
./build_ios.sh

# Copy libraries to expected locations
echo ""
echo "=== Copying libraries to Xcode project ==="

# Create Frameworks directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/Frameworks"

# Copy device library (arm64)
if [ -f "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libmob_beam_ios.a" ]; then
    cp "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libmob_beam_ios.a" \
       "$SCRIPT_DIR/Frameworks/libmob_beam_ios_device.a"
    echo "✓ Copied device library"
else
    echo "✗ Device library not found"
    exit 1
fi

# Copy simulator libraries
if [ -f "$SCRIPT_DIR/rust/target/aarch64-apple-ios-sim/release/libmob_beam_ios.a" ] && \
   [ -f "$SCRIPT_DIR/rust/target/x86_64-apple-ios/release/libmob_beam_ios.a" ]; then
    # Create universal simulator library
    lipo -create \
        "$SCRIPT_DIR/rust/target/aarch64-apple-ios-sim/release/libmob_beam_ios.a" \
        "$SCRIPT_DIR/rust/target/x86_64-apple-ios/release/libmob_beam_ios.a" \
        -output "$SCRIPT_DIR/Frameworks/libmob_beam_ios_simulator.a"
    echo "✓ Created universal simulator library"
else
    echo "✗ Simulator libraries not found"
    exit 1
fi

# Copy driver table library
if [ -f "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libdriver_tab_ios.a" ]; then
    cp "$SCRIPT_DIR/rust/target/aarch64-apple-ios/release/libdriver_tab_ios.a" \
       "$SCRIPT_DIR/Frameworks/libdriver_tab_ios_device.a"
    echo "✓ Copied driver table device library"
else
    echo "✗ Driver table device library not found"
    exit 1
fi

echo ""
echo "=== Build complete ==="
echo "Libraries are in: $SCRIPT_DIR/Frameworks/"
echo ""
echo "Next steps:"
echo "1. Open Xcode project"
echo "2. Add the .a files from Frameworks/ to your project"
echo "3. Ensure they're linked in Build Settings > Link Binary With Libraries"
echo "4. Add a Run Script build phase to call this script automatically"
