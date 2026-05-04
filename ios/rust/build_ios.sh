#!/bin/bash
# build_ios.sh - Build Rust libraries for iOS
# This script builds the Rust code for iOS targets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$SCRIPT_DIR/rust"

# iOS targets
TARGETS=(
    "aarch64-apple-ios"      # ARM64 device
    "aarch64-apple-ios-sim"  # ARM64 simulator (Apple Silicon Mac)
    "x86_64-apple-ios"       # x86_64 simulator (Intel Mac)
)

echo "Building for iOS targets..."

# Install targets if not present
for target in "${TARGETS[@]}"; do
    if ! rustup target list --installed | grep -q "$target"; then
        echo "Installing target: $target"
        rustup target add "$target"
    fi
done

# Build for each target
cd "$RUST_DIR"

for target in "${TARGETS[@]}"; do
    echo "Building for $target..."
    cargo build --target "$target" --release

    echo "Built: $RUST_DIR/target/$target/release/libmob_beam_ios.a"
done

# Create XCFramework (optional, requires xcodebuild)
echo ""
echo "To create XCFramework, run:"
echo "mkdir -p ios-framework"
echo "for target in ${TARGETS[@]}; do"
echo "  cp $RUST_DIR/target/\$target/release/libmob_beam_ios.a ios-framework/\$target-libmob_beam_ios.a"
echo "done"
echo ""
echo "iOS build complete!"
echo "Static libraries are in: $RUST_DIR/target/*/release/"

# Optional: Create universal library for simulator
echo ""
echo "Creating universal simulator library..."
SIM_ARM64="$RUST_DIR/target/aarch64-apple-ios-sim/release/libmob_beam_ios.a"
SIM_X86_64="$RUST_DIR/target/x86_64-apple-ios/release/libmob_beam_ios.a"
UNIVERSAL_SIM="$RUST_DIR/target/universal-sim-libmob_beam_ios.a"

if [ -f "$SIM_ARM64" ] && [ -f "$SIM_X86_64" ]; then
    lipo -create "$SIM_ARM64" "$SIM_X86_64" -output "$UNIVERSAL_SIM"
    echo "Created universal simulator library: $UNIVERSAL_SIM"
else
    echo "Skipping universal library - not all simulator builds present"
fi
