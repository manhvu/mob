# Mob Onboarding Integration Test Plan

## Goal

Verify that a new user can go from zero to a running Mob app — on both iOS and Android, across all supported toolchain variants — without hitting any friction that should have been caught automatically. Every test runs in a throwaway environment that is fully torn down on success.

---

## 1. Scope

### What this tests

- `mix mob.new` generates a structurally valid project
- `mix mob.install` downloads OTP runtimes and builds dependency tree
- `mix mob.doctor` passes clean
- `mix mob.deploy --native` produces a running app on a live simulator/emulator
- The home screen renders with the correct content
- Theme switching works
- Hot-push (`mix mob.push`) changes code on the running app without restart
- `mix mob.connect` attaches an IEx session and `Mob.Test` can read state

### What this does NOT test

- Performance
- Physical devices (CI is simulator/emulator only)
- App Store build pipeline
- Production distribution

---

## 2. Test Matrix

### 2a. Toolchain versions

| Dimension | Minimum | Maximum | Notes |
|-----------|---------|---------|-------|
| Elixir | 1.18.0 | 1.19.x (latest) | mob requires `~> 1.17`; keep min as 1.18 for forward safety |
| OTP | 27.0 | 28.x (latest) | |
| Hex | 2.0.0 | latest | |

### 2b. Package managers / environment types

| Environment | Tool | Isolation mechanism |
|-------------|------|---------------------|
| `mise` | `mise use elixir@1.18.x` | `.mise.toml` in temp dir |
| `asdf` | `.tool-versions` file | `.tool-versions` in temp dir |
| `homebrew` | `brew install elixir@1.18` | PATH manipulation |
| `nix` | `nix develop` with pinned flake | hermetic nix shell |

The Nix environment is **highest priority** — it is the currently failing path and has distinct failure modes from all others (see §6).

### 2c. iOS simulators

| Slot | Runtime | Device type | Rationale |
|------|---------|-------------|-----------|
| `ios-min` | iOS 16.0 | iPhone SE (3rd gen) | Minimum deployment target in `build.sh` |
| `ios-max` | iOS 26.4 (current) | iPhone 17 | Latest available runtime |

> **Note:** iOS 16.0 requires downloading the runtime via `xcrun simctl runtime add` or Xcode → Platforms. The CI workflow must install it if absent. iOS 17–25 are not needed — the goal is min/max coverage only.

### 2d. Android emulators

| Slot | API level | System image | ABI | Rationale |
|------|-----------|--------------|-----|-----------|
| `android-min` | API 28 | `google_apis` | `arm64-v8a` | `minSdk 28` in `app/build.gradle` |
| `android-max` | API 35 | `google_apis` | `arm64-v8a` | Latest available system image |

### 2e. Full CI matrix

Each cell is one independent test run. Priority order (most important first):

| Run | Toolchain env | Elixir | OTP | iOS | Android |
|-----|--------------|--------|-----|-----|---------|
| A | nix | 1.18.x | 27 | ios-max | android-max |
| B | mise | 1.19.x | 28 | ios-max | android-max |
| C | mise | 1.18.x | 27 | ios-min | android-min |
| D | asdf | 1.19.x | 28 | ios-max | android-max |
| E | homebrew | 1.19.x | 28 | ios-max | — (Android only on Linux) |

Runs A and B must pass before a release. C validates minimum version support. D and E are regression guards.

---

## 3. Environment Isolation

Each test run operates in a fully isolated workspace:

```
/tmp/mob_onboarding_<run_id>/
├── workspace/          ← WORK_DIR: mix mob.new generates project here
├── toolchain/          ← version manager installs land here (mise/asdf home)
├── mix_home/           ← MIX_HOME: separate archive/dep cache per run
├── hex_home/           ← HEX_HOME: separate Hex cache per run
└── logs/               ← stdout/stderr capture for every step
```

Key environment overrides applied for every run:

```bash
export WORK_DIR=/tmp/mob_onboarding_$RUN_ID
export MIX_HOME=$WORK_DIR/mix_home
export HEX_HOME=$WORK_DIR/hex_home
export HOME_OVERRIDE=$WORK_DIR/toolchain   # used by mise/asdf
export MOB_CACHE_DIR=$WORK_DIR/mob_cache   # overrides ~/.mob/cache
```

This ensures:
- No cross-contamination with the developer's real environment
- No cached archives or deps from previous runs leak in
- The `~/.mob/cache` OTP download lands in the temp dir

### Teardown

On **success**: the entire `WORK_DIR` is deleted.

On **failure**: `WORK_DIR` is preserved and its path is printed. Logs, the generated project, and any partial downloads are available for inspection.

---

## 4. Device Lifecycle Management

### 4a. iOS simulator

All management goes through `xcrun simctl`. Each test run creates a **dedicated simulator instance** with a unique name (`mob-onboarding-<run_id>`) so parallel runs never share state.

```bash
# Download runtime if absent (iOS 16 for min run)
xcrun simctl runtime add "com.apple.CoreSimulator.SimRuntime.iOS-16-0"

# Create a fresh simulator
SIM_ID=$(xcrun simctl create "mob-onboarding-$RUN_ID" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation" \
  "com.apple.CoreSimulator.SimRuntime.iOS-16-0")

# Boot it
xcrun simctl boot "$SIM_ID"

# Wait until it reaches 'Booted' state
until xcrun simctl list devices | grep "$SIM_ID" | grep -q "Booted"; do sleep 1; done

# ... run tests ...

# Teardown
xcrun simctl shutdown "$SIM_ID"
xcrun simctl delete "$SIM_ID"
```

### 4b. Android emulator

All management goes through `avdmanager` + `emulator`. Each run creates a dedicated AVD.

```bash
# Install system image if absent
sdkmanager "system-images;android-28;google_apis;arm64-v8a"
sdkmanager "system-images;android-35;google_apis;arm64-v8a"

# Create AVD
echo "no" | avdmanager create avd \
  --name "mob_onboarding_$RUN_ID" \
  --package "system-images;android-28;google_apis;arm64-v8a" \
  --device "pixel_6"

# Start emulator (headless)
emulator -avd "mob_onboarding_$RUN_ID" \
  -no-window -no-audio -no-boot-anim \
  -gpu swiftshader_indirect &
EMULATOR_PID=$!

# Wait for device to come online
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done'

# ... run tests ...

# Teardown
kill $EMULATOR_PID
avdmanager delete avd --name "mob_onboarding_$RUN_ID"
```

### 4c. Port assignment

To support parallel runs, each run gets a dedicated emulator port range. Pass `-port <port>` to `emulator` and derive the ADB serial from it (`emulator-<port>`):

```bash
EMULATOR_PORT=$((5554 + ($RUN_INDEX * 2)))
ADB_SERIAL="emulator-$EMULATOR_PORT"
```

---

## 5. Test Stages and Assertions

The test is a single ExUnit suite (`test/onboarding/onboarding_test.exs`) that runs as a Mix task (`mix mob.onboarding_test`). Each stage is a `test` block; the suite is tagged `@moduletag :onboarding`.

### Stage 0 — Prerequisite check

```
assert_tool_present("elixir", min_version: "1.18.0")
assert_tool_present("mix")
assert_tool_present("adb")         # Android only
assert_tool_present("xcrun")       # iOS only
assert_tool_present("java", min_version: "17")
```

Fail fast here with a clear message rather than a confusing error later.

### Stage 1 — `mix archive.install hex mob_new`

```
run("mix archive.install hex mob_new --force", in: WORK_DIR)
assert_exit_code(0)
assert run("mix archive") includes "mob_new-"
```

### Stage 2 — `mix mob.new my_app`

```
run("mix mob.new my_app", in: WORK_DIR)
assert_exit_code(0)
assert_dir_exists("my_app/lib/my_app")
assert_file_exists("my_app/lib/my_app/home_screen.ex")
assert_file_exists("my_app/android/app/src/main/assets/mob_logo_light.png")
assert_file_exists("my_app/android/app/src/main/assets/mob_logo_dark.png")
assert_file_exists("my_app/ios/build.sh")
assert_file_content("my_app/lib/my_app/home_screen.ex", ~r/use Mob\.Screen/)
assert_file_content("my_app/ios/build.sh", ~r/mob_logo/)
```

### Stage 3 — `mix mob.install`

```
run("mix mob.install", in: WORK_DIR/my_app, timeout: 300_000)
assert_exit_code(0)
assert_dir_exists("$MOB_CACHE_DIR/otp-ios-sim-*/erts-*")    # iOS
assert_dir_exists("$MOB_CACHE_DIR/otp-android-*/erts-*")     # Android
assert_file_exists("$MOB_CACHE_DIR/otp-ios-sim-*/my_app")    # beams dir
```

The OTP download is the highest-risk step. On Nix the `curl` path must be the system curl — assert that download used `:httpc` (or `/usr/bin/curl` as fallback) and not a Nix-shelled curl.

### Stage 4 — `mix mob.doctor`

```
output = run("mix mob.doctor", in: WORK_DIR/my_app)
assert_exit_code(0)
assert output includes "✓ Elixir"
assert output includes "✓ OTP"
assert output includes "✓ OTP Android" or "✓ OTP iOS simulator"
assert output does NOT include "✗"          # no hard failures
```

### Stage 5 — `mix mob.deploy --native --ios/android`

```
run("mix mob.deploy --native --ios", env: %{"MOB_IOS_SIM_ID" => sim_id}, timeout: 180_000)
assert_exit_code(0)
assert adb/simctl confirms app is installed:
  iOS:     xcrun simctl listapps $SIM_ID | grep "com.mob.my_app"
  Android: adb -s $ADB_SERIAL shell pm list packages | grep "com.mob.my_app"
```

### Stage 6 — App launches and renders

```
# Launch the app
xcrun simctl launch $SIM_ID com.mob.my_app          # iOS
adb -s $ADB_SERIAL shell am start \
  -n com.mob.my_app/.MainActivity                    # Android

# Connect distribution
run("mix mob.connect --no-iex", timeout: 30_000)
assert node_visible(:"my_app_ios@127.0.0.1")          # or android variant

# Verify home screen rendered
screen = Mob.Test.screen(node)
assert screen == MyApp.HomeScreen

assigns = Mob.Test.assigns(node)
assert assigns.theme == :obsidian

# Verify logo image node is present
tree = Mob.Test.tree(node)
assert_node_present(tree, type: "image", prop: "src", matches: ~r/mob_logo/)

# Verify three nav buttons exist
assert length(Mob.Test.find(node, "Text Input")) == 1
assert length(Mob.Test.find(node, "Browse List")) == 1
assert length(Mob.Test.find(node, "Roll Dice")) == 1

# Verify three theme buttons exist
assert length(Mob.Test.find(node, "Obsidian")) == 1
assert length(Mob.Test.find(node, "Citrus")) == 1
assert length(Mob.Test.find(node, "Birch")) == 1
```

### Stage 7 — Basic interaction

```
# Tap Citrus theme button
Mob.Test.tap(node, :theme_citrus)
:sys.get_state(Mob.Test.screen_pid(node))   # sync point
assigns = Mob.Test.assigns(node)
assert assigns.theme == :citrus

# Navigate to text input screen
Mob.Test.tap(node, :open_text)
assert Mob.Test.screen(node) == MyApp.TextScreen

# Navigate back
Mob.Test.pop(node)
assert Mob.Test.screen(node) == MyApp.HomeScreen
```

### Stage 8 — Hot-push

```
# Modify home_screen.ex — change the subtitle text
patch_file("my_app/lib/my_app/home_screen.ex",
  old: ~s(text="BEAM running on device"),
  new: ~s(text="onboarding test patched"))

run("mix mob.push", in: WORK_DIR/my_app, timeout: 30_000)
assert_exit_code(0)

# Give the running process time to pick up new code
:timer.sleep(500)
Mob.Test.tap(node, :theme_obsidian)   # any event forces code reload
:sys.get_state(Mob.Test.screen_pid(node))

# Confirm updated text is in the tree
tree = Mob.Test.tree(node)
assert_node_present(tree, type: "text", prop: "text", value: "onboarding test patched")
```

### Stage 9 — Teardown

```
xcrun simctl shutdown $SIM_ID
xcrun simctl delete $SIM_ID          # iOS

adb -s $ADB_SERIAL emu kill          # Android
avdmanager delete avd --name "mob_onboarding_$RUN_ID"

File.rm_rf!(WORK_DIR)                # only on success
```

---

## 6. Nix-Specific Handling

Nix is the highest-risk environment based on `user_issues.md`. The test matrix runs Nix first (Run A).

### 6a. Nix test flake

The Nix run uses a hermetic `flake.nix` that pins exact package versions:

```nix
# test/onboarding/nix/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };
  outputs = { self, nixpkgs }: {
    devShells.aarch64-darwin.default = let
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in pkgs.mkShell {
      buildInputs = [
        pkgs.elixir_1_18
        pkgs.erlang_27
        # Explicitly NOT including curl — forces :httpc / system curl usage
        pkgs.git
        pkgs.gnumake
      ];
      # Ensure system curl is found before Nix curl
      shellHook = ''
        export PATH="/usr/bin:$PATH"
        export SSL_CERT_FILE=""   # unset Nix cert override, use system
      '';
    };
  };
}
```

### 6b. Nix-specific assertions

Run these in addition to the standard assertions when `env == :nix`:

```
# Verify elixir_lib is auto-detected, not read from mob.exs
assert mob_exs does NOT contain "elixir_lib:"

# Verify OTP download used :httpc (not shelled curl)
assert_log_contains("OTP download", ~r/httpc|system curl/)

# Verify Elixir path is current (not stale Nix store path)
elixir_lib = :code.lib_dir(:elixir) |> Path.dirname()
assert File.dir?(elixir_lib)
assert String.contains?(elixir_lib, "elixir-1.18")
```

### 6c. Known Nix failure modes to detect

| Failure | Detection | Message shown |
|---------|-----------|---------------|
| Nix curl SSL error | OTP cache dir exists but empty / no `erts-*` | "OTP download failed. Try: `mix mob.install --use-system-curl`" |
| Stale `elixir_lib` in mob.exs | `File.exists?(elixir_lib)` returns false | "elixir_lib path is stale — re-run `mix mob.install`" |
| Old Elixir from Nix channel | `mix mob.doctor` Elixir version check fails | "Elixir 1.x found, 1.18+ required. Update your flake: `elixir_1_18`" |
| adb/xcrun not in Nix PATH | Stage 0 prerequisite check | "adb not found. Add `android-tools` to your Nix shell." |

---

## 7. Test Runner Implementation

### 7a. Mix task entry point

```
test/onboarding/
├── PLAN.md                    ← this document
├── onboarding_test.exs        ← ExUnit test suite
├── support/
│   ├── device_manager.ex      ← iOS/Android lifecycle helpers
│   ├── env_bootstrap.sh       ← shell: installs Elixir for given env type
│   ├── assertions.ex          ← assert_node_present, assert_tool_present, etc.
│   └── workspace.ex           ← creates/tears down WORK_DIR
├── nix/
│   └── flake.nix              ← pinned Nix dev shell
└── envs/
    ├── mise.toml.template      ← parameterised by Elixir/OTP version
    ├── tool-versions.template  ← asdf equivalent
    └── nix_flake.lock         ← pinned nixpkgs hash
```

Run a specific environment:

```bash
mix mob.onboarding_test --env nix --elixir 1.18 --otp 27 \
                        --ios ios-min --android android-min
```

Run the full matrix:

```bash
mix mob.onboarding_test --all
```

### 7b. Key timeouts

| Stage | Timeout |
|-------|---------|
| `mix mob.install` (OTP download) | 10 min |
| `mix mob.deploy --native` (first build) | 5 min |
| Emulator cold boot | 3 min |
| `mix mob.connect` | 30 sec |
| Hot-push | 30 sec |

---

## 8. CI/CD Integration (GitHub Actions)

```yaml
# .github/workflows/onboarding.yml
name: Onboarding Integration Tests

on:
  push:
    branches: [main]
  pull_request:
    paths:
      - 'lib/**'
      - 'priv/templates/**'
      - 'test/onboarding/**'
  schedule:
    - cron: '0 6 * * *'   # nightly at 06:00 UTC

jobs:
  onboarding:
    strategy:
      fail-fast: false
      matrix:
        include:
          - run: A
            env: nix
            elixir: "1.18"
            otp: "27"
            ios: ios-max
            android: android-max
            priority: critical

          - run: B
            env: mise
            elixir: "1.19"
            otp: "28"
            ios: ios-max
            android: android-max
            priority: critical

          - run: C
            env: mise
            elixir: "1.18"
            otp: "27"
            ios: ios-min
            android: android-min
            priority: standard

          - run: D
            env: asdf
            elixir: "1.19"
            otp: "28"
            ios: ios-max
            android: android-max
            priority: standard

    runs-on: macos-15    # Apple Silicon; required for iOS simulator + ARM Android

    steps:
      - uses: actions/checkout@v4

      - name: Install Nix (Run A only)
        if: matrix.env == 'nix'
        uses: cachix/install-nix-action@v26
        with:
          nix_path: nixpkgs=channel:nixos-24.05

      - name: Install mise (non-Nix)
        if: matrix.env == 'mise'
        run: curl https://mise.run | sh

      - name: Install asdf (Run D only)
        if: matrix.env == 'asdf'
        uses: asdf-vm/actions/setup@v3

      - name: Install Android SDK components
        run: |
          sdkmanager "system-images;android-28;google_apis;arm64-v8a"
          sdkmanager "system-images;android-35;google_apis;arm64-v8a"
          sdkmanager "emulator" "platform-tools" "build-tools;34.0.0"

      - name: Install iOS 16 runtime (Run C only)
        if: matrix.ios == 'ios-min'
        run: |
          xcrun simctl runtime add "com.apple.CoreSimulator.SimRuntime.iOS-16-0" || true
          # iOS 16 runtime may need download from Apple CDN via Xcode

      - name: Run onboarding test
        run: |
          mix mob.onboarding_test \
            --env ${{ matrix.env }} \
            --elixir ${{ matrix.elixir }} \
            --otp ${{ matrix.otp }} \
            --ios ${{ matrix.ios }} \
            --android ${{ matrix.android }} \
            --run-id ${{ matrix.run }}
        timeout-minutes: 30

      - name: Upload failure artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: onboarding-failure-run-${{ matrix.run }}
          path: /tmp/mob_onboarding_${{ matrix.run }}/logs/
          retention-days: 7
```

---

## 9. Failure Reporting

Each step writes structured output to `$WORK_DIR/logs/<step>.log`. On failure, the runner prints:

```
=== Onboarding Test FAILED — Run B (mise / Elixir 1.19 / OTP 28) ===

Failed at: Stage 3 — mix mob.install
Duration:  47s
Exit code: 1

Last 20 lines of output:
  ...
  ERROR: No erts-* directory found in /tmp/mob_onboarding_B/mob_cache/otp-ios-sim-73ba6e0f
         Have you built OTP for iOS simulator?

Workspace preserved at: /tmp/mob_onboarding_B/
  logs/          ← per-step stdout/stderr
  my_app/        ← generated project state
  mob_cache/     ← OTP download state (check for empty dirs)

Likely cause: OTP download silently failed. Check logs/03_mob_install.log.
```

---

## 10. What to Build First

In priority order:

1. **`DeviceManager`** — iOS simulator and Android emulator create/boot/teardown. Blocking everything else.
2. **Stage 0–4** (generation through `mob.doctor`) — highest ROI, catches the Nix failures and the most common setup errors. Can run headlessly with no device.
3. **Nix flake** — pin the exact nixpkgs commit that corresponds to the currently failing `Nova` environment.
4. **Stages 5–7** (deploy, launch, basic interaction) — requires devices; build after DeviceManager is solid.
5. **Stage 8** (hot-push) — last, as it depends on everything upstream working.
6. **CI workflow** — wire it all together once the local runner is green.
