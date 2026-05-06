#!/bin/bash
# ios_setup.sh - Automated iOS Bluetooth/WiFi setup for Dala
# Usage: ./scripts/ios_setup.sh [options] [path_to_ios_directory]
#
# This script:
# 1. Finds the Xcode project/workspace in the ios/ directory
# 2. Adds Bluetooth files to the Xcode project (Ruby or sed fallback)
# 3. Links CoreBluetooth.framework
# 4. Adds required Info.plist entries for Bluetooth and WiFi usage
# 5. Patches AppDelegate to call DalaBluetoothBridge.ensureLinked()
# 6. Verifies the setup
#
# Options:
#   --check    Verify current setup without making changes
#   --no-color Disable colored output
#   --help     Show this help message

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────

COLOR_ENABLED=true
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { $COLOR_ENABLED && echo -e "${GREEN}[INFO]${NC} $1"  || echo "[INFO] $1"; }
log_warn()  { $COLOR_ENABLED && echo -e "${YELLOW}[WARN]${NC} $1" || echo "[WARN] $1"; }
log_error() { $COLOR_ENABLED && echo -e "${RED}[ERROR]${NC} $1"   || echo "[ERROR] $1"; }
log_check() { $COLOR_ENABLED && echo -e "${CYAN}[CHECK]${NC} $1"  || echo "[CHECK] $1"; }

# ── Parse arguments ───────────────────────────────────────────────────────────

CHECK_MODE=false
IOS_DIR=""

for arg in "$@"; do
    case "$arg" in
        --check)    CHECK_MODE=true ;;
        --no-color) COLOR_ENABLED=false ;;
        --help|-h)
            echo "Usage: $0 [options] [path_to_ios_directory]"
            echo ""
            echo "Options:"
            echo "  --check      Verify current setup without making changes"
            echo "  --no-color   Disable colored output"
            echo "  --help       Show this help message"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $arg"
            exit 1
            ;;
        *)
            IOS_DIR="$arg"
            ;;
    esac
done

# Determine ios directory
IOS_DIR="${IOS_DIR:-$(dirname "$0")/../ios}"
IOS_DIR="$(cd "$IOS_DIR" && pwd)"

log_info "iOS directory: $IOS_DIR"

# ── Tool availability ─────────────────────────────────────────────────────────

has_ruby()   { command -v ruby &>/dev/null; }
has_plutil() { command -v plutil &>/dev/null; }
has_xcodebuild() { command -v xcodebuild &>/dev/null; }
has_sed()    { command -v sed &>/dev/null; }
has_plistbuddy() { [[ -x /usr/libexec/PlistBuddy ]]; }

# ── Bluetooth source files ────────────────────────────────────────────────────

BLUETOOTH_FILES=(
    "DalaBluetoothManager.h"
    "DalaBluetoothManager.m"
    "DalaBluetoothCInterface.m"
    "DalaBluetooth.swift"
)

check_bluetooth_files() {
    local missing=0
    for file in "${BLUETOOTH_FILES[@]}"; do
        if [[ ! -f "$IOS_DIR/$file" ]]; then
            log_error "Missing required file: $IOS_DIR/$file"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -gt 0 ]]; then
        return 1
    fi
    log_info "All Bluetooth source files found."
    return 0
}

# ── Find Xcode project ────────────────────────────────────────────────────────

find_xcode_project() {
    local dir="$1"

    # Look for .xcworkspace first (preferred for CocoaPods)
    local workspace
    workspace=$(find "$dir" -maxdepth 2 -name "*.xcworkspace" -type d 2>/dev/null | head -n 1)
    if [[ -n "$workspace" ]]; then
        echo "$workspace"
        return 0
    fi

    # Look for .xcodeproj
    local project
    project=$(find "$dir" -maxdepth 2 -name "*.xcodeproj" -type d 2>/dev/null | head -n 1)
    if [[ -n "$project" ]]; then
        echo "$project"
        return 0
    fi

    return 1
}

# ── Find Info.plist ───────────────────────────────────────────────────────────

find_info_plist() {
    find "$IOS_DIR" -maxdepth 3 -name "Info.plist" -type f 2>/dev/null | head -n 1
}

# ── Find AppDelegate ──────────────────────────────────────────────────────────
# Returns the path and type: "swift", "objc", "swiftui_app", or ""

find_app_delegate() {
    local dir="$1"

    # Swift AppDelegate
    local swift_delegate
    swift_delegate=$(find "$dir" -maxdepth 3 -name "AppDelegate.swift" -type f 2>/dev/null | head -n 1)
    if [[ -n "$swift_delegate" ]]; then
        # Check if it has @main or UIApplicationDelegate — real AppDelegate
        if grep -qE 'UIApplicationDelegate|@main' "$swift_delegate" 2>/dev/null; then
            echo "swift:$swift_delegate"
            return 0
        fi
    fi

    # Objective-C AppDelegate
    local objc_delegate
    objc_delegate=$(find "$dir" -maxdepth 3 -name "AppDelegate.m" -type f 2>/dev/null | head -n 1)
    if [[ -n "$objc_delegate" ]]; then
        echo "objc:$objc_delegate"
        return 0
    fi

    # SwiftUI App struct (no AppDelegate) — look for @main App struct
    local app_swift
    app_swift=$(find "$dir" -maxdepth 3 -name "*.swift" -type f 2>/dev/null | xargs grep -l '@main' 2>/dev/null | head -n 1)
    if [[ -n "$app_swift" ]]; then
        echo "swiftui_app:$app_swift"
        return 0
    fi

    echo "none:"
    return 0
}

# ── Patch AppDelegate (Swift) ─────────────────────────────────────────────────

patch_swift_app_delegate() {
    local file="$1"

    # Already patched?
    if grep -q 'DalaBluetoothBridge.ensureLinked' "$file" 2>/dev/null; then
        log_info "AppDelegate already contains DalaBluetoothBridge.ensureLinked() call."
        return 0
    fi

    # Add import CoreBluetooth if missing
    if ! grep -q 'import CoreBluetooth' "$file" 2>/dev/null; then
        sed -i '' '1s/^/import CoreBluetooth\n/' "$file"
    fi

    # Insert DalaBluetoothBridge.ensureLinked() in didFinishLaunchingWithOptions
    if grep -q 'didFinishLaunchingWithOptions' "$file"; then
        # Find the first `return true` inside didFinishLaunchingWithOptions and insert before it
        sed -i '' '/didFinishLaunchingWithOptions/,/return true/{
            /return true/i\
\        DalaBluetoothBridge.ensureLinked()
        }' "$file"
        log_info "Added DalaBluetoothBridge.ensureLinked() to AppDelegate.swift"
    else
        # No didFinishLaunchingWithOptions — add it
        # Find the class body and add the method
        sed -i '' '/class AppDelegate/,/^}/{
            /^}/i\
\
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {\
        DalaBluetoothBridge.ensureLinked()\
        return true\
    }
        }' "$file"
        log_info "Added didFinishLaunchingWithOptions with DalaBluetoothBridge.ensureLinked() to AppDelegate.swift"
    fi
}

# ── Patch AppDelegate (Objective-C) ───────────────────────────────────────────

patch_objc_app_delegate() {
    local file="$1"

    # Already patched?
    if grep -q 'DalaBluetoothBridge.ensureLinked' "$file" 2>/dev/null; then
        log_info "AppDelegate already contains DalaBluetoothBridge.ensureLinked() call."
        return 0
    fi

    # Add import if missing
    if ! grep -q 'DalaBluetoothBridge' "$file" 2>/dev/null; then
        # For ObjC, we need to call the ObjC class method directly
        # DalaBluetoothBridge is a Swift class, accessible via bridging header
        if ! grep -q '@class DalaBluetoothBridge' "$file" 2>/dev/null; then
            sed -i '' '1s/^/@class DalaBluetoothBridge;\n/' "$file"
        fi
    fi

    # Insert in didFinishLaunchingWithOptions
    if grep -q 'didFinishLaunchingWithOptions' "$file"; then
        sed -i '' '/didFinishLaunchingWithOptions/,/return YES/{
            /return YES/i\
    [DalaBluetoothBridge ensureLinked];
        }' "$file"
        log_info "Added [DalaBluetoothBridge ensureLinked] to AppDelegate.m"
    else
        log_warn "Could not find didFinishLaunchingWithOptions in AppDelegate.m"
        log_warn "Add this line manually inside didFinishLaunchingWithOptions:"
        log_warn "  [DalaBluetoothBridge ensureLinked];"
    fi
}

# ── Create minimal AppDelegate for SwiftUI apps ──────────────────────────────

create_swiftui_app_delegate() {
    local app_file="$1"
    local dir
    dir=$(dirname "$app_file")

    local delegate_file="$dir/DalaAppDelegate.swift"

    if [[ -f "$delegate_file" ]]; then
        if grep -q 'DalaBluetoothBridge.ensureLinked' "$delegate_file" 2>/dev/null; then
            log_info "DalaAppDelegate.swift already exists with Bluetooth initialization."
            return 0
        fi
    fi

    cat > "$delegate_file" <<'SWIFT'
// DalaAppDelegate.swift - Auto-generated by Dala iOS setup
// Provides Bluetooth initialization for SwiftUI app lifecycle apps

import UIKit
import CoreBluetooth

class DalaAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        DalaBluetoothBridge.ensureLinked()
        return true
    }
}
SWIFT

    log_info "Created $delegate_file with DalaBluetoothBridge.ensureLinked()"

    # Now patch the @main App struct to use the AppDelegate
    if grep -q '@main' "$app_file" 2>/dev/null; then
        # Add UIApplicationDelegateAdaptor if not already present
        if ! grep -q 'UIApplicationDelegateAdaptor' "$app_file" 2>/dev/null; then
            # Find the App struct body and add the adaptor
            sed -i '' '/@main/,/^}/{
                /struct.*App.*:.*App/{
                    n
                    i\
    @UIApplicationDelegateAdaptor(DalaAppDelegate.self) var appDelegate
                }
            }' "$app_file"
            log_info "Added UIApplicationDelegateAdaptor to @main App struct in $(basename "$app_file")"
        else
            log_info "UIApplicationDelegateDelegateAdaptor already present in $(basename "$app_file")"
        fi
    fi
}

# ── Patch AppDelegate (dispatch to correct handler) ──────────────────────────

patch_app_delegate() {
    local dir="$1"
    local result
    result=$(find_app_delegate "$dir")

    local type="${result%%:*}"
    local path="${result#*:}"

    case "$type" in
        swift)
            log_info "Found Swift AppDelegate: $path"
            patch_swift_app_delegate "$path"
            ;;
        objc)
            log_info "Found Objective-C AppDelegate: $path"
            patch_objc_app_delegate "$path"
            ;;
        swiftui_app)
            log_info "Found SwiftUI App lifecycle (no AppDelegate): $path"
            create_swiftui_app_delegate "$path"
            ;;
        none)
            log_warn "No AppDelegate or @main App struct found."
            log_warn "Create an AppDelegate and add: DalaBluetoothBridge.ensureLinked()"
            ;;
    esac
}

# ── Modify pbxproj with Ruby ──────────────────────────────────────────────────

modify_pbxproj_ruby() {
    local pbxproj="$1"
    local ios_dir="$2"

    ruby <<-RUBY
require 'tempfile'

pbxproj_path = "$pbxproj"
ios_dir = "$ios_dir"

content = File.read(pbxproj_path)

bluetooth_files = [
  { name: 'DalaBluetoothManager.h', is_header: true },
  { name: 'DalaBluetoothManager.m', is_header: false },
  { name: 'DalaBluetoothCInterface.m', is_header: false },
  { name: 'DalaBluetooth.swift', is_header: false }
]

def generate_id
  (0...24).map { |i| i.even? ? ('A'..'F').to_a.sample : ('0'..'9').to_a.sample }.join
end

# Find the main group and Sources build phase
main_group_id = nil
sources_build_phase_id = nil

if content =~ /^\s*([A-F0-9]{24})\s*\/\* \w+ \*\/ = \{\s*$/
  main_group_id = $1
end

if content =~ /^\s*([A-F0-9]{24})\s*\/\* Sources \*\/ = \{\s*$/
  sources_build_phase_id = $1
end

if main_group_id.nil? || sources_build_phase_id.nil?
  # Try broader patterns
  content.scan(/^\s*([A-F0-9]{24})\s*\/\* (\w+) \*\/ = \{$/) do |id, name|
    # Heuristic: the main group is usually named after the project
    if main_group_id.nil?
      main_group_id = id
    end
  end

  content.scan(/^\s*([A-F0-9]{24})\s*\/\* Sources \*\/ = \{$/) do |id|
    sources_build_phase_id = id
  end
end

if main_group_id.nil? || sources_build_phase_id.nil?
  $stderr.puts "ERROR: Could not find required project sections (main_group=#{main_group_id}, sources=#{sources_build_phase_id})"
  exit 1
end

# Check if files are already added
already_added = false
bluetooth_files.each do |file|
  if content.include?(file[:name])
    already_added = true
    break
  end
end

if already_added
  puts "INFO: Bluetooth files already exist in project, skipping pbxproj modification"
  exit 0
end

# Generate IDs
file_refs = {}
bluetooth_files.each do |file|
  file_refs[file[:name]] = { id: generate_id, ref_id: generate_id }
end

# Build PBXFileReference entries
file_reference_entries = ""
file_refs.each do |name, ids|
  if name.end_with?('.h')
    file_reference_entries += "    #{ids[:ref_id]} /* #{name} */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.h; path = #{name}; sourceTree = \"<group>\"; };\n"
  elsif name.end_with?('.m')
    file_reference_entries += "    #{ids[:ref_id]} /* #{name} */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.objc; path = #{name}; sourceTree = \"<group>\"; };\n"
  elsif name.end_with?('.swift')
    file_reference_entries += "    #{ids[:ref_id]} /* #{name} */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = #{name}; sourceTree = \"<group>\"; };\n"
  end
end

# Insert file references into PBXFileReference section
if content =~ /\/\* Begin PBXFileReference section \*\/\n/
  content = content.sub(
    /\/\* Begin PBXFileReference section \*\/\n/,
    "/* Begin PBXFileReference section */\n#{file_reference_entries}"
  )
end

# Build PBXBuildFile entries
build_file_entries = ""
file_refs.each do |name, ids|
  build_file_entries += "    #{ids[:id]} /* #{name} in Sources */ = {isa = PBXBuildFile; fileRef = #{ids[:ref_id]} /* #{name} */; };\n"
end

# Insert build files into PBXBuildFile section
if content =~ /\/\* Begin PBXBuildFile section \*\/\n/
  content = content.sub(
    /\/\* Begin PBXBuildFile section \*\/\n/,
    "/* Begin PBXBuildFile section */\n#{build_file_entries}"
  )
end

# Add files to main group children
file_ref_ids = file_refs.map { |_, ids| ids[:ref_id] }.join(', ')
# Match the main group's children list
if content =~ /(#{Regexp.escape(main_group_id)}\s*\/\* \w+ \*\/ = \{\s*\n\s*isa = PBXGroup;\s*\n\s*children = \(\s*\n)/m
  content = content.sub($1, $1 + "      #{file_ref_ids},\n")
end

# Add files to Sources build phase
build_file_ids = file_refs.map { |_, ids| ids[:id] }.join(', ')
if content =~ /(#{Regexp.escape(sources_build_phase_id)}\s*\/\* Sources \*\/ = \{\s*\n\s*isa = PBXSourcesBuildPhase;\s*\n\s*buildActionMask = 2147483647;\s*\n\s*files = \(\s*\n)/m
  content = content.sub($1, $1 + "      #{build_file_ids},\n")
end

# Add CoreBluetooth.framework if not present
unless content.include?('CoreBluetooth.framework')
  framework_id = generate_id
  framework_ref_id = generate_id

  framework_entry = "    #{framework_ref_id} /* CoreBluetooth.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = CoreBluetooth.framework; path = System/Library/Frameworks/CoreBluetooth.framework; sourceTree = SDKROOT; };\n"
  framework_build_entry = "    #{framework_id} /* CoreBluetooth.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = #{framework_ref_id} /* CoreBluetooth.framework */; };\n"

  # Insert into PBXFileReference section
  if content =~ /\/\* Begin PBXFileReference section \*\/\n/
    content = content.sub(
      /\/\* Begin PBXFileReference section \*\/\n/,
      "/* Begin PBXFileReference section */\n#{framework_entry}"
    )
  end

  # Insert into PBXBuildFile section
  if content =~ /\/\* Begin PBXBuildFile section \*\/\n/
    content = content.sub(
      /\/\* Begin PBXBuildFile section \*\/\n/,
      "/* Begin PBXBuildFile section */\n#{framework_build_entry}"
    )
  end

  # Add to Frameworks group
  if content =~ /([A-F0-9]{24})\s*\/\* Frameworks \*\/ = \{\s*\n\s*isa = PBXGroup;\s*\n\s*children = \(\s*\n/m
    content = content.sub($&) { "#{$&}      #{framework_ref_id},\n" }
  end

  # Add to Frameworks build phase
  if content =~ /([A-F0-9]{24})\s*\/\* Frameworks \*\/ = \{\s*\n\s*isa = PBXFrameworksBuildPhase;\s*\n\s*buildActionMask = 2147483647;\s*\n\s*files = \(\s*\n/m
    content = content.sub($&) { "#{$&}      #{framework_id},\n" }
  end
end

# Write back
File.write(pbxproj_path, content)
puts "SUCCESS: Updated #{pbxproj_path}"
RUBY
}

# ── Modify pbxproj fallback (sed-based, minimal) ─────────────────────────────
# When Ruby is not available, we add files to the project by appending
# to the relevant sections. This is less robust but works for simple projects.

modify_pbxproj_sed() {
    local pbxproj="$1"

    # Check if files are already in the project
    if grep -q 'DalaBluetoothManager.h' "$pbxproj" 2>/dev/null; then
        log_info "Bluetooth files already exist in project (detected via sed), skipping."
        return 0
    fi

    log_warn "Ruby not available — using sed fallback for pbxproj modification."
    log_warn "This is less robust. Verify the project in Xcode after setup."

    # Generate pseudo-unique IDs (24 hex chars)
    local ref_h=$(openssl rand -hex 12 2>/dev/null || echo "A1B2C3D4E5F6A1B2C3D4E5F6" | head -c 24)
    local ref_m=$(openssl rand -hex 12 2>/dev/null || echo "B2C3D4E5F6A1B2C3D4E5F6A1" | head -c 24)
    local ref_c=$(openssl rand -hex 12 2>/dev/null || echo "C3D4E5F6A1B2C3D4E5F6A1B2" | head -c 24)
    local ref_s=$(openssl rand -hex 12 2>/dev/null || echo "D4E5F6A1B2C3D4E5F6A1B2C3" | head -c 24)
    local build_h=$(openssl rand -hex 12 2>/dev/null || echo "E5F6A1B2C3D4E5F6A1B2C3D4" | head -c 24)
    local build_m=$(openssl rand -hex 12 2>/dev/null || echo "F6A1B2C3D4E5F6A1B2C3D4E5" | head -c 24)
    local build_c=$(openssl rand -hex 12 2>/dev/null || echo "A1B2C3D4E5F6A1B2C3D4E5F7" | head -c 24)
    local build_s=$(openssl rand -hex 12 2>/dev/null || echo "B2C3D4E5F6A1B2C3D4E5F6A2" | head -c 24)

    # Add file references to PBXFileReference section
    sed -i '' "/\/\* Begin PBXFileReference section \*\//a\\
    ${ref_h} /* DalaBluetoothManager.h */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.h; path = DalaBluetoothManager.h; sourceTree = \"<group>\"; };\\
    ${ref_m} /* DalaBluetoothManager.m */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.objc; path = DalaBluetoothManager.m; sourceTree = \"<group>\"; };\\
    ${ref_c} /* DalaBluetoothCInterface.m */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.c.objc; path = DalaBluetoothCInterface.m; sourceTree = \"<group>\"; };\\
    ${ref_s} /* DalaBluetooth.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = DalaBluetooth.swift; sourceTree = \"<group>\"; };
" "$pbxproj"

    # Add build file entries to PBXBuildFile section
    sed -i '' "/\/\* Begin PBXBuildFile section \*\//a\\
    ${build_h} /* DalaBluetoothManager.h in Sources */ = {isa = PBXBuildFile; fileRef = ${ref_h} /* DalaBluetoothManager.h */; };\\
    ${build_m} /* DalaBluetoothManager.m in Sources */ = {isa = PBXBuildFile; fileRef = ${ref_m} /* DalaBluetoothManager.m */; };\\
    ${build_c} /* DalaBluetoothCInterface.m in Sources */ = {isa = PBXBuildFile; fileRef = ${ref_c} /* DalaBluetoothCInterface.m */; };\\
    ${build_s} /* DalaBluetooth.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${ref_s} /* DalaBluetooth.swift */; };
" "$pbxproj"

    # Add CoreBluetooth.framework if not present
    if ! grep -q 'CoreBluetooth.framework' "$pbxproj" 2>/dev/null; then
        local fw_ref=$(openssl rand -hex 12 2>/dev/null || echo "C3D4E5F6A1B2C3D4E5F6A1B3" | head -c 24)
        local fw_build=$(openssl rand -hex 12 2>/dev/null || echo "D4E5F6A1B2C3D4E5F6A1B2C4" | head -c 24)

        sed -i '' "/\/\* Begin PBXFileReference section \*\//a\\
    ${fw_ref} /* CoreBluetooth.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = CoreBluetooth.framework; path = System/Library/Frameworks/CoreBluetooth.framework; sourceTree = SDKROOT; };
" "$pbxproj"

        sed -i '' "/\/\* Begin PBXBuildFile section \*\//a\\
    ${fw_build} /* CoreBluetooth.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${fw_ref} /* CoreBluetooth.framework */; };
" "$pbxproj"

        # Add to Frameworks group children
        sed -i '' "/Frameworks \*\/ = {/{
            N;N;N
            s/children = (/children = (\\
                ${fw_ref},/
        }" "$pbxproj" 2>/dev/null || true

        # Add to Frameworks build phase
        sed -i '' "/PBXFrameworksBuildPhase/,/files = (/{
            s/files = (/files = (\\
                ${fw_build},/
        }" "$pbxproj" 2>/dev/null || true
    fi

    log_info "pbxproj modified via sed fallback. Please verify in Xcode."
}

# ── Modify Xcode project ─────────────────────────────────────────────────────

modify_xcode_project() {
    local pbxproj="$1"

    if [[ ! -f "$pbxproj" ]]; then
        log_error "project.pbxproj not found at $pbxproj"
        return 1
    fi

    # Check if files already exist in project
    if grep -q 'DalaBluetoothManager.h' "$pbxproj" 2>/dev/null && \
       grep -q 'DalaBluetooth.swift' "$pbxproj" 2>/dev/null; then
        log_info "Bluetooth files already in Xcode project."
    else
        log_info "Modifying Xcode project file..."
        if has_ruby; then
            if modify_pbxproj_ruby "$pbxproj" "$IOS_DIR"; then
                log_info "Xcode project updated successfully (via Ruby)."
            else
                log_error "Ruby-based pbxproj modification failed."
                log_info "Falling back to sed-based modification..."
                modify_pbxproj_sed "$pbxproj"
            fi
        else
            log_warn "Ruby not found — using sed fallback for pbxproj modification."
            modify_pbxproj_sed "$pbxproj"
        fi
    fi

    # Verify CoreBluetooth.framework is linked
    if grep -q 'CoreBluetooth.framework' "$pbxproj" 2>/dev/null; then
        log_info "CoreBluetooth.framework is referenced in the project."
    else
        log_warn "CoreBluetooth.framework may not be linked. Add it manually in Xcode:"
        log_warn "  Target → Build Phases → Link Binary With Libraries → + → CoreBluetooth.framework"
    fi
}

# ── Update Info.plist ─────────────────────────────────────────────────────────

update_info_plist() {
    local plist="$1"

    if [[ -z "$plist" ]]; then
        log_warn "Info.plist not found. You will need to manually add usage descriptions."
        log_warn "Required keys:"
        log_warn "  NSBluetoothAlwaysUsageDescription"
        log_warn "  NSBluetoothPeripheralUsageDescription"
        log_warn "  NSLocalNetworkUsageDescription"
        return 0
    fi

    log_info "Found Info.plist: $plist"

    # ── Bluetooth usage descriptions ──────────────────────────────────────

    local bt_desc="This app uses Bluetooth to connect to nearby devices."

    if has_plutil; then
        # NSBluetoothAlwaysUsageDescription (iOS 13+)
        plutil -insert NSBluetoothAlwaysUsageDescription -string "$bt_desc" "$plist" 2>/dev/null || \
            plutil -replace NSBluetoothAlwaysUsageDescription -string "$bt_desc" "$plist" 2>/dev/null || \
            log_warn "Could not set NSBluetoothAlwaysUsageDescription via plutil"

        # NSBluetoothPeripheralUsageDescription (iOS 12 and earlier)
        plutil -insert NSBluetoothPeripheralUsageDescription -string "$bt_desc" "$plist" 2>/dev/null || \
            plutil -replace NSBluetoothPeripheralUsageDescription -string "$bt_desc" "$plist" 2>/dev/null || \
            log_warn "Could not set NSBluetoothPeripheralUsageDescription via plutil"
    elif has_plistbuddy; then
        /usr/libexec/PlistBuddy -c "Add :NSBluetoothAlwaysUsageDescription string '$bt_desc'" "$plist" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c "Set :NSBluetoothAlwaysUsageDescription '$bt_desc'" "$plist" 2>/dev/null || \
            log_warn "Could not set NSBluetoothAlwaysUsageDescription via PlistBuddy"

        /usr/libexec/PlistBuddy -c "Add :NSBluetoothPeripheralUsageDescription string '$bt_desc'" "$plist" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c "Set :NSBluetoothPeripheralUsageDescription '$bt_desc'" "$plist" 2>/dev/null || \
            log_warn "Could not set NSBluetoothPeripheralUsageDescription via PlistBuddy"
    else
        log_warn "Neither plutil nor PlistBuddy available."
        log_warn "Manually add these keys to Info.plist:"
        log_warn "  NSBluetoothAlwaysUsageDescription = \"$bt_desc\""
        log_warn "  NSBluetoothPeripheralUsageDescription = \"$bt_desc\""
    fi

    # ── WiFi / Local Network usage descriptions (iOS 14+) ─────────────────

    local wifi_desc="This app needs local network access to discover and communicate with nearby devices."

    if has_plutil; then
        # NSLocalNetworkUsageDescription (iOS 14+)
        plutil -insert NSLocalNetworkUsageDescription -string "$wifi_desc" "$plist" 2>/dev/null || \
            plutil -replace NSLocalNetworkUsageDescription -string "$wifi_desc" "$plist" 2>/dev/null || \
            log_warn "Could not set NSLocalNetworkUsageDescription via plutil"

        # Bonjour services (required for local network access on iOS 14+)
        if ! plutil -extract NSBonjourServices xml1 "$plist" &>/dev/null; then
            plutil -insert NSBonjourServices -xml "<array><string>_dala._tcp</string></array>" "$plist" 2>/dev/null || \
                log_warn "Could not set NSBonjourServices via plutil"
        else
            # Append _dala._tcp if not already present
            if ! plutil -p "$plist" | grep -q '_dala._tcp'; then
                plutil -insert NSBonjourServices.0 -string "_dala._tcp" "$plist" 2>/dev/null || \
                    log_warn "Could not append _dala._tcp to NSBonjourServices"
            fi
        fi
    elif has_plistbuddy; then
        /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string '$wifi_desc'" "$plist" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c "Set :NSLocalNetworkUsageDescription '$wifi_desc'" "$plist" 2>/dev/null || \
            log_warn "Could not set NSLocalNetworkUsageDescription via PlistBuddy"

        /usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "$plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :NSBonjourServices:0 string '_dala._tcp'" "$plist" 2>/dev/null || \
            log_warn "Could not add _dala._tcp to NSBonjourServices via PlistBuddy"
    else
        log_warn "Manually add these keys to Info.plist:"
        log_warn "  NSLocalNetworkUsageDescription = \"$wifi_desc\""
        log_warn "  NSBonjourServices = [\"_dala._tcp\"]"
    fi

    # ── UIBackgroundModes for Bluetooth ───────────────────────────────────

    if has_plutil; then
        # Check if UIBackgroundModes already exists
        if ! plutil -extract UIBackgroundModes xml1 "$plist" &>/dev/null; then
            plutil -insert UIBackgroundModes -xml "<array><string>bluetooth-central</string></array>" "$plist" 2>/dev/null || \
                log_warn "Could not set UIBackgroundModes via plutil"
        else
            # Add bluetooth-central if not present
            if ! plutil -p "$plist" | grep -q 'bluetooth-central'; then
                local count
                count=$(plutil -extract UIBackgroundModes xml1 -o - "$plist" 2>/dev/null | grep -c '<string>' || echo "0")
                plutil -insert "UIBackgroundModes.$count" -string "bluetooth-central" "$plist" 2>/dev/null || \
                    log_warn "Could not add bluetooth-central to UIBackgroundModes"
            fi
        fi
    elif has_plistbuddy; then
        /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$plist" 2>/dev/null || true
        if ! /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$plist" 2>/dev/null | grep -q 'bluetooth-central'; then
            local count
            count=$(/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$plist" 2>/dev/null | wc -l | tr -d ' ')
            /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:$count string 'bluetooth-central'" "$plist" 2>/dev/null || \
                log_warn "Could not add bluetooth-central to UIBackgroundModes via PlistBuddy"
        fi
    fi

    log_info "Info.plist updated with Bluetooth and WiFi usage descriptions."
}

# ── Verification ──────────────────────────────────────────────────────────────

verify_setup() {
    local errors=0
    local warnings=0

    echo ""
    log_check "Verifying iOS Bluetooth/WiFi setup..."
    echo ""

    # 1. Bluetooth source files
    log_check "1. Bluetooth source files"
    for file in "${BLUETOOTH_FILES[@]}"; do
        if [[ -f "$IOS_DIR/$file" ]]; then
            log_info "   ✓ $file"
        else
            log_error "   ✗ $file — MISSING"
            errors=$((errors + 1))
        fi
    done

    # 2. Xcode project
    log_check "2. Xcode project"
    local xcode_proj
    xcode_proj=$(find_xcode_project "$IOS_DIR" 2>/dev/null || true)
    if [[ -n "$xcode_proj" ]]; then
        log_info "   ✓ Found: $(basename "$xcode_proj")"

        local pbxproj="$xcode_proj/project.pbxproj"
        if [[ -f "$pbxproj" ]]; then
            # Check Bluetooth files in project
            if grep -q 'DalaBluetoothManager.h' "$pbxproj" 2>/dev/null; then
                log_info "   ✓ DalaBluetoothManager.h in project"
            else
                log_warn "   ⚠ DalaBluetoothManager.h not in project"
                warnings=$((warnings + 1))
            fi

            if grep -q 'DalaBluetooth.swift' "$pbxproj" 2>/dev/null; then
                log_info "   ✓ DalaBluetooth.swift in project"
            else
                log_warn "   ⚠ DalaBluetooth.swift not in project"
                warnings=$((warnings + 1))
            fi

            # Check CoreBluetooth.framework
            if grep -q 'CoreBluetooth.framework' "$pbxproj" 2>/dev/null; then
                log_info "   ✓ CoreBluetooth.framework linked"
            else
                log_warn "   ⚠ CoreBluetooth.framework not linked"
                warnings=$((warnings + 1))
            fi
        fi
    else
        log_error "   ✗ No Xcode project found"
        errors=$((errors + 1))
    fi

    # 3. Info.plist
    log_check "3. Info.plist entries"
    local info_plist
    info_plist=$(find_info_plist)
    if [[ -n "$info_plist" ]]; then
        log_info "   Found: $info_plist"

        local plist_keys=(
            "NSBluetoothAlwaysUsageDescription:Bluetooth always permission"
            "NSBluetoothPeripheralUsageDescription:Bluetooth peripheral permission"
            "NSLocalNetworkUsageDescription:Local network permission"
            "NSBonjourServices:Bonjour services"
            "UIBackgroundModes:Background modes"
        )

        for entry in "${plist_keys[@]}"; do
            local key="${entry%%:*}"
            local label="${entry#*:}"

            if has_plutil; then
                if plutil -extract "$key" xml1 "$info_plist" &>/dev/null; then
                    log_info "   ✓ $label ($key)"
                else
                    log_warn "   ⚠ $label ($key) — MISSING"
                    warnings=$((warnings + 1))
                fi
            elif has_plistbuddy; then
                if /usr/libexec/PlistBuddy -c "Print :$key" "$info_plist" &>/dev/null; then
                    log_info "   ✓ $label ($key)"
                else
                    log_warn "   ⚠ $label ($key) — MISSING"
                    warnings=$((warnings + 1))
                fi
            else
                log_warn "   ⚠ Cannot verify $label (no plutil/PlistBuddy)"
                warnings=$((warnings + 1))
            fi
        done
    else
        log_error "   ✗ Info.plist not found"
        errors=$((errors + 1))
    fi

    # 4. AppDelegate
    log_check "4. AppDelegate Bluetooth initialization"
    local result
    result=$(find_app_delegate "$IOS_DIR")
    local type="${result%%:*}"
    local path="${result#*:}"

    case "$type" in
        swift)
            log_info "   Found Swift AppDelegate: $(basename "$path")"
            if grep -q 'DalaBluetoothBridge.ensureLinked' "$path" 2>/dev/null; then
                log_info "   ✓ DalaBluetoothBridge.ensureLinked() present"
            else
                log_warn "   ⚠ DalaBluetoothBridge.ensureLinked() NOT present"
                warnings=$((warnings + 1))
            fi
            ;;
        objc)
            log_info "   Found Objective-C AppDelegate: $(basename "$path")"
            if grep -q 'DalaBluetoothBridge.ensureLinked\|ensureLinked' "$path" 2>/dev/null; then
                log_info "   ✓ DalaBluetoothBridge.ensureLinked present"
            else
                log_warn "   ⚠ DalaBluetoothBridge.ensureLinked NOT present"
                warnings=$((warnings + 1))
            fi
            ;;
        swiftui_app)
            log_info "   Found SwiftUI App lifecycle: $(basename "$path")"
            # Check for DalaAppDelegate.swift
            local delegate_dir
            delegate_dir=$(dirname "$path")
            if [[ -f "$delegate_dir/DalaAppDelegate.swift" ]]; then
                log_info "   ✓ DalaAppDelegate.swift exists"
                if grep -q 'DalaBluetoothBridge.ensureLinked' "$delegate_dir/DalaAppDelegate.swift" 2>/dev/null; then
                    log_info "   ✓ DalaBluetoothBridge.ensureLinked() present"
                else
                    log_warn "   ⚠ DalaBluetoothBridge.ensureLinked() NOT present in DalaAppDelegate.swift"
                    warnings=$((warnings + 1))
                fi
            else
                log_warn "   ⚠ DalaAppDelegate.swift not found (needed for SwiftUI apps)"
                warnings=$((warnings + 1))
            fi
            # Check UIApplicationDelegateAdaptor
            if grep -q 'UIApplicationDelegateAdaptor' "$path" 2>/dev/null; then
                log_info "   ✓ UIApplicationDelegateAdaptor present"
            else
                log_warn "   ⚠ UIApplicationDelegateAdaptor NOT present in App struct"
                warnings=$((warnings + 1))
            fi
            ;;
        none)
            log_warn "   ⚠ No AppDelegate or @main App struct found"
            warnings=$((warnings + 1))
            ;;
    esac

    # 5. Bridging header
    log_check "5. Bridging header"
    local bridging_header
    bridging_header=$(find "$IOS_DIR" -maxdepth 2 -name "*Bridging-Header.h" -type f 2>/dev/null | head -n 1)
    if [[ -n "$bridging_header" ]]; then
        log_info "   Found: $(basename "$bridging_header")"
        if grep -q 'DalaBluetoothManager' "$bridging_header" 2>/dev/null; then
            log_info "   ✓ DalaBluetoothManager.h referenced in bridging header"
        else
            log_warn "   ⚠ DalaBluetoothManager.h not in bridging header"
            log_warn "     Add: #import \"DalaBluetoothManager.h\""
            warnings=$((warnings + 1))
        fi
    else
        log_warn "   ⚠ No bridging header found"
        warnings=$((warnings + 1))
    fi

    # Summary
    echo ""
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        log_info "✅ All checks passed!"
    elif [[ $errors -eq 0 ]]; then
        log_warn "⚠️  $warnings warning(s) found. Review above."
    else
        log_error "❌ $errors error(s) and $warnings warning(s) found. Fix errors before building."
    fi

    return $errors
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    # Check prerequisites
    if ! check_bluetooth_files; then
        log_error "Bluetooth source files are missing. Cannot proceed."
        exit 1
    fi

    # Find Xcode project
    XCODE_PROJECT=$(find_xcode_project "$IOS_DIR" 2>/dev/null || true)

    if [[ -z "$XCODE_PROJECT" ]]; then
        log_error "No Xcode project or workspace found in $IOS_DIR"
        log_info "Please create an Xcode project first, or specify the correct path."
        exit 1
    fi

    log_info "Found Xcode project: $XCODE_PROJECT"

    # --check mode: just verify and exit
    if $CHECK_MODE; then
        verify_setup
        exit $?
    fi

    # ── Step 1: Modify Xcode project ──────────────────────────────────────

    PBXPROJ="$XCODE_PROJECT/project.pbxproj"
    modify_xcode_project "$PBXPROJ"

    # ── Step 2: Update Info.plist ─────────────────────────────────────────

    INFO_PLIST=$(find_info_plist)
    update_info_plist "$INFO_PLIST"

    # ── Step 3: Patch AppDelegate ─────────────────────────────────────────

    log_info "Patching AppDelegate for Bluetooth initialization..."
    patch_app_delegate "$IOS_DIR"

    # ── Step 4: Verify ────────────────────────────────────────────────────

    verify_setup

    # ── Done ──────────────────────────────────────────────────────────────

    echo ""
    log_info "========================================"
    log_info "iOS Bluetooth/WiFi setup completed!"
    log_info "========================================"
    echo ""
    log_info "Next steps:"
    log_info "1. Open your Xcode project: $XCODE_PROJECT"
    log_info "2. Verify Bluetooth files are added to the project"
    log_info "3. Verify CoreBluetooth.framework is linked"
    log_info "4. Verify Info.plist contains usage descriptions"
    log_info "5. Build and run your project"
    echo ""
    log_info "To verify setup at any time:"
    log_info "  $0 --check"
    echo ""
    log_info "To test Bluetooth in your Elixir code:"
    log_info "  Dala.Bluetooth.state()"
    log_info "  Dala.Bluetooth.start_scan(socket)"
}

main
