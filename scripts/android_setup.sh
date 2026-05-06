#!/bin/bash
# android_setup.sh - Automated Android Bluetooth/WiFi setup for Dala
# Usage: ./scripts/android_setup.sh [path_to_android_directory]
#
# This script:
# 1. Finds the Android project directory (android/ or app/src/main/)
# 2. Checks for AndroidManifest.xml
# 3. Adds required Bluetooth and WiFi permissions to AndroidManifest.xml
# 4. Adds uses-feature for bluetooth_le with required=false
# 5. Checks for DalaBridge.java and copies it if missing
# 6. Checks if DalaBridge.init() is called in MainActivity
# 7. Verifies the setup at the end

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# =========================================================================
# Resolve paths
# =========================================================================

# Determine the script's directory (for finding framework files)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DALA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Determine android directory — accept arg, or look for android/ at project root
if [[ -n "$1" ]]; then
    ANDROID_DIR="$(cd "$1" && pwd)"
else
    ANDROID_DIR="$(cd "$DALA_ROOT/android" 2>/dev/null && pwd)" || true
    if [[ -z "$ANDROID_DIR" ]]; then
        # Try finding android/ from current working directory
        ANDROID_DIR="$(cd "android" 2>/dev/null && pwd)" || true
    fi
fi

if [[ -z "$ANDROID_DIR" ]]; then
    log_error "Android directory not found."
    log_info "Usage: $0 [path_to_android_directory]"
    exit 1
fi

log_info "Android directory: $ANDROID_DIR"

# =========================================================================
# Step 1: Find AndroidManifest.xml
# =========================================================================

log_step "1/7  Finding AndroidManifest.xml..."

find_manifest() {
    local dir="$1"

    # Common locations, in order of preference
    local candidates=(
        "$dir/app/src/main/AndroidManifest.xml"
        "$dir/src/main/AndroidManifest.xml"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    # Broader search
    local found
    found=$(find "$dir" -name "AndroidManifest.xml" -type f 2>/dev/null | head -n 1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi

    return 1
}

MANIFEST=$(find_manifest "$ANDROID_DIR")

if [[ -z "$MANIFEST" ]]; then
    log_error "AndroidManifest.xml not found in $ANDROID_DIR"
    log_info "Make sure you're pointing at a valid Android project directory."
    exit 1
fi

log_info "Found AndroidManifest.xml: $MANIFEST"

# Determine the source root (parent of AndroidManifest.xml's "main/" dir)
# e.g. /path/android/app/src/main/AndroidManifest.xml → /path/android/app/src/main
MANIFEST_DIR="$(dirname "$MANIFEST")"

# =========================================================================
# Step 2: Add Bluetooth permissions
# =========================================================================

log_step "2/7  Adding Bluetooth permissions to AndroidManifest.xml..."

# Permissions to add (name + optional extra attributes)
# Format: "permission_name|extra_xml_attrs"
BLUETOOTH_PERMISSIONS=(
    "android.permission.BLUETOOTH|"
    "android.permission.BLUETOOTH_ADMIN|"
    "android.permission.BLUETOOTH_SCAN|android:usesPermissionFlags=\"neverForLocation\""
    "android.permission.BLUETOOTH_CONNECT|"
    "android.permission.ACCESS_FINE_LOCATION|"
    "android.permission.ACCESS_COARSE_LOCATION|"
)

add_permission_if_missing() {
    local manifest="$1"
    local permission="$2"
    local extra_attrs="$3"

    # Check if this permission already exists (with or without extra attributes)
    if grep -q "android:name=\"${permission}\"" "$manifest"; then
        log_warn "Permission ${permission} already exists — skipping"
        return 0
    fi

    # Build the <uses-permission> tag
    local tag="<uses-permission android:name=\"${permission}\""
    if [[ -n "$extra_attrs" ]]; then
        tag="${tag} ${extra_attrs}"
    fi
    tag="${tag} />"

    # Insert before the <application> tag
    if grep -q "<application" "$manifest"; then
        # Use a temp file for macOS compatibility (sed -i differs)
        local tmp
        tmp=$(mktemp)
        sed "s|<application|${tag}\n    <application|" "$manifest" > "$tmp"
        mv "$tmp" "$manifest"
        log_info "Added permission: ${permission}"
    else
        log_error "No <application> tag found in $manifest — cannot add permission"
        return 1
    fi
}

for entry in "${BLUETOOTH_PERMISSIONS[@]}"; do
    IFS='|' read -r perm attrs <<< "$entry"
    add_permission_if_missing "$MANIFEST" "$perm" "$attrs"
done

# =========================================================================
# Step 3: Add WiFi permissions
# =========================================================================

log_step "3/7  Adding WiFi permissions to AndroidManifest.xml..."

WIFI_PERMISSIONS=(
    "android.permission.ACCESS_WIFI_STATE|"
    "android.permission.CHANGE_WIFI_STATE|"
)

for entry in "${WIFI_PERMISSIONS[@]}"; do
    IFS='|' read -r perm attrs <<< "$entry"
    add_permission_if_missing "$MANIFEST" "$perm" "$attrs"
done

# =========================================================================
# Step 4: Add uses-feature for bluetooth_le
# =========================================================================

log_step "4/7  Adding uses-feature for bluetooth_le..."

add_uses_feature_if_missing() {
    local manifest="$1"
    local feature_name="$2"
    local required="$3"

    if grep -q "android:name=\"${feature_name}\"" "$manifest"; then
        log_warn "uses-feature ${feature_name} already exists — skipping"
        return 0
    fi

    local tag="<uses-feature android:name=\"${feature_name}\" android:required=\"${required}\" />"

    if grep -q "<application" "$manifest"; then
        local tmp
        tmp=$(mktemp)
        sed "s|<application|${tag}\n    <application|" "$manifest" > "$tmp"
        mv "$tmp" "$manifest"
        log_info "Added uses-feature: ${feature_name} (required=${required})"
    else
        log_error "No <application> tag found in $manifest"
        return 1
    fi
}

add_uses_feature_if_missing "$MANIFEST" "android.hardware.bluetooth_le" "false"

# =========================================================================
# Step 5: Check for DalaBridge.java
# =========================================================================

log_step "5/7  Checking for DalaBridge.java..."

# Find the Java/Kotlin source root (typically src/main/java or src/main/kotlin)
find_java_source_root() {
    local manifest_dir="$1"

    # Walk up from the manifest dir to find src/main/java
    local base
    base="$(dirname "$manifest_dir")"  # src/main

    if [[ -d "$base/java" ]]; then
        echo "$base/java"
        return 0
    fi

    if [[ -d "$base/kotlin" ]]; then
        echo "$base/kotlin"
        return 0
    fi

    # Broader search
    local found
    found=$(find "$base" -type d -name "java" 2>/dev/null | head -n 1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi

    return 1
}

JAVA_SRC_ROOT=$(find_java_source_root "$MANIFEST_DIR")

if [[ -z "$JAVA_SRC_ROOT" ]]; then
    log_error "Could not find Java/Kotlin source root (expected src/main/java or src/main/kotlin)"
    exit 1
fi

log_info "Java source root: $JAVA_SRC_ROOT"

# Determine the package path from AndroidManifest.xml's package attribute
PACKAGE_NAME=$(grep -o 'package="[^"]*"' "$MANIFEST" | head -n 1 | sed 's/package="//;s/"//')

if [[ -z "$PACKAGE_NAME" ]]; then
    log_warn "Could not determine package name from AndroidManifest.xml"
    log_warn "Defaulting to com.example.dala"
    PACKAGE_NAME="com.example.dala"
fi

log_info "Package name: $PACKAGE_NAME"

# Convert package name to path (com.example.dala → com/example/dala)
PACKAGE_PATH="${PACKAGE_NAME//.//}"
DALA_BRIDGE_DIR="$JAVA_SRC_ROOT/$PACKAGE_PATH"
DALA_BRIDGE_FILE="$DALA_BRIDGE_DIR/DalaBridge.java"

# Framework's DalaBridge.java source
FRAMEWORK_BRIDGE="$DALA_ROOT/android/src/main/java/com/example/dala/DalaBridge.java"

if [[ -f "$DALA_BRIDGE_FILE" ]]; then
    log_info "DalaBridge.java already exists at: $DALA_BRIDGE_FILE"
else
    log_warn "DalaBridge.java not found at: $DALA_BRIDGE_FILE"

    if [[ -f "$FRAMEWORK_BRIDGE" ]]; then
        log_info "Copying DalaBridge.java from framework..."

        mkdir -p "$DALA_BRIDGE_DIR"
        cp "$FRAMEWORK_BRIDGE" "$DALA_BRIDGE_FILE"

        # Update the package declaration if the package name differs
        if [[ "$PACKAGE_NAME" != "com.example.dala" ]]; then
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i '' "s/^package com\.example\.dala;/package ${PACKAGE_NAME};/" "$DALA_BRIDGE_FILE"
            else
                sed -i "s/^package com\.example\.dala;/package ${PACKAGE_NAME};/" "$DALA_BRIDGE_FILE"
            fi
            log_info "Updated package declaration to: $PACKAGE_NAME"
        fi

        log_info "DalaBridge.java copied to: $DALA_BRIDGE_FILE"
    else
        log_error "Framework DalaBridge.java not found at: $FRAMEWORK_BRIDGE"
        log_info "You will need to add DalaBridge.java manually."
    fi
fi

# =========================================================================
# Step 6: Check if DalaBridge.init() is called in MainActivity
# =========================================================================

log_step "6/7  Checking for DalaBridge.init() in MainActivity..."

find_main_activity() {
    local src_root="$1"
    local pkg_path="$2"

    # Check for Java and Kotlin files
    local candidates=(
        "$src_root/$pkg_path/MainActivity.java"
        "$src_root/$pkg_path/MainActivity.kt"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    # Broader search for any MainActivity
    local found
    found=$(find "$src_root" -name "MainActivity.*" -type f 2>/dev/null | head -n 1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi

    return 1
}

MAIN_ACTIVITY=$(find_main_activity "$JAVA_SRC_ROOT" "$PACKAGE_PATH") || true

if [[ -z "$MAIN_ACTIVITY" ]]; then
    log_warn "MainActivity not found in $JAVA_SRC_ROOT"
    log_warn ""
    log_warn "You need to call DalaBridge.init() in your MainActivity's onCreate:"
    log_warn ""
    log_warn "  // Java"
    log_warn "  @Override"
    log_warn "  protected void onCreate(Bundle savedInstanceState) {"
    log_warn "      super.onCreate(savedInstanceState);"
    log_warn "      DalaBridge.init(this);  // <-- Add this line"
    log_warn "  }"
    log_warn ""
    log_warn "  // Kotlin"
    log_warn "  override fun onCreate(savedInstanceState: Bundle?) {"
    log_warn "      super.onCreate(savedInstanceState)"
    log_warn "      DalaBridge.init(this)  // <-- Add this line"
    log_warn "  }"
else
    log_info "Found MainActivity: $MAIN_ACTIVITY"

    if grep -q "DalaBridge\.init" "$MAIN_ACTIVITY"; then
        log_info "DalaBridge.init() is already called in MainActivity ✓"
    else
        log_warn "DalaBridge.init() is NOT called in MainActivity"
        log_warn ""
        log_warn "Add the following to your MainActivity's onCreate method:"

        # Detect language from file extension
        EXT="${MAIN_ACTIVITY##*.}"

        if [[ "$EXT" == "kt" ]]; then
            log_warn ""
            log_warn "  // In $MAIN_ACTIVITY"
            log_warn "  import ${PACKAGE_NAME}.DalaBridge"
            log_warn ""
            log_warn "  override fun onCreate(savedInstanceState: Bundle?) {"
            log_warn "      super.onCreate(savedInstanceState)"
            log_warn "      DalaBridge.init(this)  // Initialize Dala bridge"
            log_warn "  }"
        else
            log_warn ""
            log_warn "  // In $MAIN_ACTIVITY"
            log_warn "  import ${PACKAGE_NAME}.DalaBridge;"
            log_warn ""
            log_warn "  @Override"
            log_warn "  protected void onCreate(Bundle savedInstanceState) {"
            log_warn "      super.onCreate(savedInstanceState);"
            log_warn "      DalaBridge.init(this);  // Initialize Dala bridge"
            log_warn "  }"
        fi

        # Also check if the import is present
        if ! grep -q "import.*DalaBridge" "$MAIN_ACTIVITY"; then
            log_warn ""
            log_warn "  Don't forget to add the import:"
            if [[ "$EXT" == "kt" ]]; then
                log_warn "  import ${PACKAGE_NAME}.DalaBridge"
            else
                log_warn "  import ${PACKAGE_NAME}.DalaBridge;"
            fi
        fi
    fi
fi

# =========================================================================
# Step 7: Verify the setup
# =========================================================================

log_step "7/7  Verifying setup..."

ERRORS=0

# Check manifest permissions
REQUIRED_PERMISSIONS=(
    "android.permission.BLUETOOTH"
    "android.permission.BLUETOOTH_ADMIN"
    "android.permission.BLUETOOTH_SCAN"
    "android.permission.BLUETOOTH_CONNECT"
    "android.permission.ACCESS_FINE_LOCATION"
    "android.permission.ACCESS_COARSE_LOCATION"
    "android.permission.ACCESS_WIFI_STATE"
    "android.permission.CHANGE_WIFI_STATE"
)

log_info "Checking AndroidManifest.xml permissions..."
for perm in "${REQUIRED_PERMISSIONS[@]}"; do
    if grep -q "android:name=\"${perm}\"" "$MANIFEST"; then
        log_info "  ✓ ${perm}"
    else
        log_error "  ✗ ${perm} — MISSING"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check BLUETOOTH_SCAN has neverForLocation flag (may be on a separate line)
if grep -q "android.permission.BLUETOOTH_SCAN" "$MANIFEST"; then
    # Use tr to collapse multi-line declarations, then check
    if tr '\n' ' ' < "$MANIFEST" | grep -q 'BLUETOOTH_SCAN.*neverForLocation\|neverForLocation.*BLUETOOTH_SCAN'; then
        log_info "  ✓ BLUETOOTH_SCAN has neverForLocation flag"
    else
        log_warn "  ⚠ BLUETOOTH_SCAN missing neverForLocation flag (recommended for Android 12+)"
    fi
fi

# Check uses-feature
log_info "Checking uses-feature declarations..."
if grep -q "android.hardware.bluetooth_le" "$MANIFEST"; then
    log_info "  ✓ android.hardware.bluetooth_le declared"
else
    log_error "  ✗ android.hardware.bluetooth_le — MISSING"
    ERRORS=$((ERRORS + 1))
fi

# Check DalaBridge.java
log_info "Checking DalaBridge.java..."
if [[ -f "$DALA_BRIDGE_FILE" ]]; then
    log_info "  ✓ DalaBridge.java exists at $DALA_BRIDGE_FILE"
else
    log_error "  ✗ DalaBridge.java — MISSING"
    ERRORS=$((ERRORS + 1))
fi

# Check DalaBridge.init() call
log_info "Checking DalaBridge.init() call..."
if [[ -n "$MAIN_ACTIVITY" ]] && grep -q "DalaBridge\.init" "$MAIN_ACTIVITY"; then
    log_info "  ✓ DalaBridge.init() called in MainActivity"
elif [[ -n "$MAIN_ACTIVITY" ]]; then
    log_warn "  ⚠ DalaBridge.init() not called in MainActivity (see instructions above)"
else
    log_warn "  ⚠ MainActivity not found — cannot verify DalaBridge.init() call"
fi

# =========================================================================
# Summary
# =========================================================================

echo ""
log_info "========================================"
if [[ $ERRORS -eq 0 ]]; then
    log_info "Android Bluetooth/WiFi setup completed! ✓"
else
    log_error "Android Bluetooth/WiFi setup completed with ${ERRORS} error(s)"
fi
log_info "========================================"
echo ""
log_info "Summary:"
log_info "  Manifest: $MANIFEST"
log_info "  Package:  $PACKAGE_NAME"
if [[ -n "$MAIN_ACTIVITY" ]]; then
    log_info "  Activity: $MAIN_ACTIVITY"
fi
if [[ -f "$DALA_BRIDGE_FILE" ]]; then
    log_info "  Bridge:   $DALA_BRIDGE_FILE"
fi
echo ""
log_info "Next steps:"
log_info "1. Review the changes to AndroidManifest.xml"
log_info "2. Ensure DalaBridge.init(this) is called in your MainActivity's onCreate"
log_info "3. Request runtime permissions for Bluetooth (Android 6+) and location"
log_info "4. Build and run your project"
echo ""
log_info "To test Bluetooth in your Elixir code:"
log_info "  Dala.Bluetooth.state()"
log_info "  Dala.Bluetooth.start_scan(socket)"
echo ""
log_info "To run a full diagnostic:"
log_info "  Dala.Setup.diagnostic()"
