# mob_demo QA Findings

QA tour performed on iOS simulator (iPhone 17, iOS 26.4) using `Mob.Test` + screenshots.
Android distribution confirmed working after SELinux fix (#5).

---

## Fixed during this tour

### 1. ListScreen crash on tap (FIXED — renderer.ex)
**Root cause:** `Mob.List.expand` generates `on_tap: {pid, {:list, id, :select, index}}` where
the tag is a tuple, but `prepare_props` called `Atom.to_string(tag)` which requires an atom.

**Fix:** Split into two clauses in `renderer.ex:284`:
```elixir
{:on_tap, {pid, tag}} when is_pid(pid) and is_atom(tag) ->
  [{"on_tap", nif.register_tap({pid, tag})}, {"accessibility_id", Atom.to_string(tag)}]

{:on_tap, {pid, tag}} when is_pid(pid) ->
  [{"on_tap", nif.register_tap({pid, tag})}]
```

### 2. TabScreen heading text invisible (FIXED — tab_screen.ex)
**Root cause:** `text_size: "2xl"` passed a string; renderer only resolves atoms.
The `@text_sizes` map key is `:"2xl"` (atom), not `"2xl"` (string).

**Fix:** Changed all three tab headings in `mob_demo/lib/mob_demo/tab_screen.ex` to use
`text_size: :"2xl"`.

### 3. TabScreen content bottom-aligned (FIXED — MobRootView.swift)
**Root cause:** `MobNodeView` inside `TabView` had no frame modifier, so SwiftUI
placed the content at the bottom of the tab area.

**Fix:** Added `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`
to the tab item content in `MobTabView` in `ios/MobRootView.swift`.

### 5. Android app doesn't start distribution (FIXED — mob_dev)
**Root cause:** Android 15 streaming `adb install` labels ERTS helper `.so` files
(`liberl_child_setup.so`, `libinet_gethost.so`, `libepmd.so`) as `app_data_file`
instead of `apk_data_file`. The `execute_no_trans` permission is denied for
`app_data_file`, so `erl_child_setup` cannot exec.

A second issue: `mob_beam.c` creates symlinks `files/otp/erts-*/bin/erl_child_setup →
nativeLibDir/liberl_child_setup.so`. The `chcon -R` calls in `deployer.ex` and
`android.ex` followed these symlinks and reset the native lib files back to
`app_data_file`, undoing the fix on every deploy and restart.

**Fixes applied in mob_dev:**
1. `native_build.ex`: Added `fix_erts_helper_labels/2` — after each APK install,
   uses `chcon u:object_r:apk_data_file:s0` on the 3 ERTS helper `.so` files
   (requires `adb root`, silently skipped on non-rooted devices).
2. `deployer.ex`: Changed both `chcon -R` calls to `chcon -hR` to prevent
   symlink dereferencing (changes symlink context, not target file context).
3. `discovery/android.ex`: Same `chcon -R` → `chcon -hR` fix in `restart_app`.

**Verified:** `mix mob.connect --no-iex` now shows both nodes connected:
```
✓ mob_demo_android@127.0.0.1  [port 9100]
✓ mob_demo_ios@127.0.0.1  [port 9101]
```

---

## Additional fixes (post-tour)

### 4. TabScreen column background doesn't fill full tab height (FIXED — MobRootView.swift)
**Root cause:** `MobTabView` outer frame has `maxHeight: .infinity` but the column's
VStack background only covers content height. The gap below had no background.

**Fix:** In `MobTabView`, capture the child node and apply its background color to
the outer full-height frame wrapper:
```swift
let child = node.childNodes[index]
MobNodeView(node: child)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(child.backgroundColor.map { Color($0) } ?? Color.clear)
```
This fills the entire tab area with the column's background color without affecting
column rendering in other contexts (scroll views, etc.).

### 6. DeviceScreen interactive buttons (PARTIALLY VERIFIED)
Non-hardware buttons verified via `Mob.Test`: haptic, clipboard write/read,
and notification scheduling all work correctly (log entries confirmed in assigns).

Fixed one bug found during review: the motion event throttle used
`rem(data.timestamp, 5) == 0` which is always true for 100ms-interval
timestamps (all divisible by 5). Fixed to `rem(div(data.timestamp, 100), 5) == 0`
which correctly logs 1 in 5 events (every 500ms at 100ms interval).

Camera, microphone, biometric, location, and scanner require hardware/permissions
and should be verified on a real device.

### 7. InputScreen text field value is nil, not "" (NOT A BUG)
`mount/3` correctly assigns `""`. Verified live: `Mob.Test.assigns/1` shows
`name: ""` after navigation. Original observation was a stale read taken before
the screen finished mounting.

---

## Screens verified working (iOS)

| Screen          | Navigation | State | Events |
|----------------|-----------|-------|--------|
| NavScreen       | ✓         | ✓     | ✓ (all 6 nav buttons) |
| CounterScreen   | ✓         | ✓     | ✓ (increment, back)   |
| ComponentsScreen| ✓         | ✓     | —                     |
| InputScreen     | ✓         | ✓     | ✓ (name, notifications, volume) |
| ListScreen      | ✓         | ✓     | ✓ (tap to select, both renderers) |
| TabScreen       | ✓         | ✓     | ✓ (tab switching works via :change) |
| DeviceScreen    | ✓         | ✓     | untested (hardware) |

## Android cluster

Android distribution confirmed working after SELinux fix. Both nodes connect reliably:
- `mob_demo_android@127.0.0.1` (port 9100)
- `mob_demo_ios@127.0.0.1` (port 9101)
