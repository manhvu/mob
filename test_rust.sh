#!/bin/bash
# test_rust.sh - Comprehensive test runner for Rust conversion
# Run this to verify the Rust code works correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Mob Rust Port Test Suite ===${NC}"
echo ""

# ============================================================================
# Test Android Rust Code
# ============================================================================
echo -e "${YELLOW}[1/4] Testing Android driver table...${NC}"
cd "$SCRIPT_DIR/android/jni/rust"

if [ -f "Cargo.toml" ]; then
    echo "Running unit tests for driver_tab_android.rs..."
    cargo test --lib -- --nocapture 2>&1 | tee /tmp/test_android_driver.log || true

    if grep -q "^test result: ok" /tmp/test_android_driver.log; then
        echo -e "${GREEN}✓ Android driver table tests passed${NC}"
    else
        echo -e "${RED}✗ Android driver table tests failed${NC}"
    fi
else
    echo -e "${RED}✗ Cargo.toml not found for Android${NC}"
fi

echo ""

# ============================================================================
# Test iOS Rust Code
# ============================================================================
echo -e "${YELLOW}[2/4] Testing iOS driver table...${NC}"
cd "$SCRIPT_DIR/ios/rust"

if [ -f "Cargo.toml" ]; then
    echo "Running unit tests for driver_tab_ios.rs..."
    cargo test --lib -- --nocapture 2>&1 | tee /tmp/test_ios_driver.log || true

    if grep -q "^test result: ok" /tmp/test_ios_driver.log; then
        echo -e "${GREEN}✓ iOS driver table tests passed${NC}"
    else
        echo -e "${RED}✗ iOS driver table tests failed${NC}"
    fi
else
    echo -e "${RED}✗ Cargo.toml not found for iOS${NC}"
fi

echo ""

# ============================================================================
# Test Android BEAM Launcher
# ============================================================================
echo -e "${YELLOW}[3/4] Testing Android BEAM launcher...${NC}"
cd "$SCRIPT_DIR/android/jni/rust"

echo "Running unit tests for mob_beam.rs..."
cargo test --lib -- --nocapture 2>&1 | tee /tmp/test_android_beam.log || true

if grep -q "^test result: ok" /tmp/test_android_beam.log; then
    echo -e "${GREEN}✓ Android BEAM launcher tests passed${NC}"
else
    echo -e "${RED}✗ Android BEAM launcher tests failed${NC}"
fi

echo ""

# ============================================================================
# Test iOS BEAM Launcher
# ============================================================================
echo -e "${YELLOW}[4/4] Testing iOS BEAM launcher...${NC}"
cd "$SCRIPT_DIR/ios/rust"

echo "Running unit tests for mob_beam_ios.rs..."
cargo test --lib -- --nocapture 2>&1 | tee /tmp/test_ios_beam.log || true

if grep -q "^test result: ok" /tmp/test_ios_beam.log; then
    echo -e "${GREEN}✓ iOS BEAM launcher tests passed${NC}"
else
    echo -e "${RED}✗ iOS BEAM launcher tests failed${NC}"
fi

echo ""
echo -e "${GREEN}=== Test Suite Complete ===${NC}"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=== Test Summary ==="
echo "Check the log files:"
echo "  - /tmp/test_android_driver.log"
echo "  - /tmp/test_ios_driver.log"
echo "  - /tmp/test_android_beam.log"
echo "  - /tmp/test_ios_beam.log"
echo ""

# ============================================================================
# Optional: Build Tests (requires targets)
# ============================================================================
if [ "$1" == "--build" ]; then
    echo -e "${YELLOW}=== Building for all targets ===${NC}"

    echo "Building Android targets..."
    cd "$SCRIPT_DIR/android/jni/rust"
    ./build_android.sh 2>&1 | tee /tmp/build_android.log || true

    echo "Building iOS targets..."
    cd "$SCRIPT_DIR/ios/rust"
    ./build_ios.sh 2>&1 | tee /tmp/build_ios.log || true

    echo ""
    echo "Build logs:"
    echo "  - /tmp/build_android.log"
    echo "  - /tmp/build_ios.log"
fi

# ============================================================================
# Optional: Integration Tests (requires built libraries)
# ============================================================================
if [ "$1" == "--integration" ]; then
    echo -e "${YELLOW}=== Running integration tests ===${NC}"

    # Test exported symbols (Android)
    ANDROID_LIB="$SCRIPT_DIR/android/jni/rust/target/aarch64-linux-android/release/libmob_beam.so"
    if [ -f "$ANDROID_LIB" ]; then
        echo "Checking Android exported symbols..."
        nm -D "$ANDROID_LIB" | grep -q "mob_start_beam" && \
            echo -e "${GREEN}✓ mob_start_beam exported${NC}" || \
            echo -e "${RED}✗ mob_start_beam not exported${NC}"
        nm -D "$ANDROID_LIB" | grep -q "driver_tab" && \
            echo -e "${GREEN}✓ driver_tab exported${NC}" || \
            echo -e "${RED}✗ driver_tab not exported${NC}"
    else
        echo -e "${RED}✗ Android library not built${NC}"
    fi

    # Test exported symbols (iOS)
    IOS_LIB="$SCRIPT_DIR/ios/rust/target/aarch64-apple-ios/release/libmob_beam_ios.a"
    if [ -f "$IOS_LIB" ]; then
        echo "Checking iOS exported symbols..."
        nm "$IOS_LIB" | grep -q "mob_start_beam" && \
            echo -e "${GREEN}✓ mob_start_beam exported${NC}" || \
            echo -e "${RED}✗ mob_start_beam not exported${NC}"
        nm "$IOS_LIB" | grep -q "driver_tab" && \
            echo -e "${GREEN}✓ driver_tab exported${NC}" || \
            echo -e "${RED}✗ driver_tab not exported${NC}"
    else
        echo -e "${RED}✗ iOS library not built${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Done!${NC}"
