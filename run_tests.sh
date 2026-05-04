#!/bin/bash
# run_tests.sh - Run all Rust tests for Mob.

set -e;
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Mob Rust Port Test Suite ===${NC}"
echo ""

# ============================================================================
# Test Android Rust Code
# ============================================================================
echo -e "${YELLOW}[1/2] Testing Android Rust code...${NC}"
cd android/jni/rust

echo "Running unit tests..."
if cargo test 2>&1 | tee /tmp/test_android.log; then
    if grep -q "^test result: ok" /tmp/test_android.log; then
        echo -e "${GREEN}✓ Android tests passed${NC}"
    else
        echo -e "${RED}✗ Android tests failed${NC}"
    fi
else
    echo -e "${RED}✗ Android compilation failed${NC}"
fi

echo ""

# ============================================================================
# Test iOS Rust Code
# ============================================================================
echo -e "${YELLOW}[2/2] Testing iOS Rust code...${NC}"
cd ios/rust

echo "Running unit tests..."
if cargo test 2>&1 | tee /tmp/test_ios.log; then
    if grep -q "^test result: ok" /tmp/test_ios.log; then
        echo -e "${GREEN}✓ iOS tests passed${NC}"
    else
        echo -e "${RED}✗ iOS tests failed${NC}"
    fi
else
    echo -e "${RED}✗ iOS compilation failed${NC}"
fi

echo ""
echo -e "${GREEN}=== Test Suite Complete ===${NC}"
echo ""
echo "Check the log files:"
echo "  - /tmp/test_android.log"
echo "  - /tmp/test_ios.log"
