# Mob

A mobile framework for Elixir that runs the full BEAM runtime on-device — no server, no JavaScript, no React Native. Native UI driven directly from Elixir via NIFs.

> **Status:** Early development. Android emulator and iOS simulator working. Not yet ready for production use.

## What it does

Mob embeds OTP into your Android/iOS app and lets you write screens in Elixir using a LiveView-inspired lifecycle:

```elixir
defmodule MyApp.CounterScreen do
  use Mob.Screen

  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :count, 0)}
  end

  def render(assigns) do
    %{
      type: :column,
      props: %{padding: 16},
      children: [
        %{type: :text,   props: %{text: "Count: #{assigns.count}"}, children: []},
        %{type: :button, props: %{text: "Increment", on_tap: self()}, children: []}
      ]
    }
  end

  def handle_info({:tap, _tag}, socket) do
    {:noreply, Mob.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
```

- **Android:** native Compose UI via JNI, no WebView
- **iOS:** SwiftUI via Objective-C NIFs, no WebView
- **State management:** `Mob.Screen` GenServer with `mount/3`, `render/1`, `handle_info/2`
- **Boot time:** ~64ms to first Elixir line on iOS simulator (M4 Pro)

## Installation

```elixir
def deps do
  [
    {:mob, "~> 0.1.0"}
  ]
end
```

## Components

Mob components are plain Elixir maps with `:type`, `:props`, and `:children` keys. The component vocabulary mirrors SwiftUI and Jetpack Compose layout primitives.

### Layout

**`column`** — stacks children vertically (VStack / Column)

```elixir
%{type: :column, props: %{padding: 16, background: :white}, children: [...]}
```

**`row`** — stacks children horizontally (HStack / Row)

```elixir
%{type: :row, props: %{padding: 8, gap: 12}, children: [...]}
```

**`box`** — overlays children (ZStack / Box). Useful for badges, overlapping elements.

```elixir
%{type: :box, props: %{}, children: [background_node, foreground_node]}
```

**`scroll`** — makes content scrollable

```elixir
%{type: :scroll, props: %{axis: :vertical, show_indicator: false}, children: [
  %{type: :column, props: %{}, children: [...]}
]}
```

| Prop | Values | Default |
|------|--------|---------|
| `axis` | `:vertical`, `:horizontal` | `:vertical` |
| `show_indicator` | `true`, `false` | `true` |

**`spacer`** — fixed-size gap

```elixir
%{type: :spacer, props: %{size: 16}, children: []}
```

**`divider`** — horizontal rule

```elixir
%{type: :divider, props: %{color: :gray_300}, children: []}
```

### Display

**`text`** — text node with full typography support

```elixir
%{type: :text, props: %{
  text:           "Hello",
  text_size:      :xl,           # see token table below
  text_color:     :gray_900,
  font_weight:    :bold,         # :bold | :semibold | :medium | :regular | :light | :thin
  text_align:     :center,       # :left | :center | :right
  italic:         true,
  line_height:    1.6,           # multiplier
  letter_spacing: 1.0,           # sp / pt
  font:           "Inter",       # custom font family name
  background:     :blue_600,
  padding:        12,
}, children: []}
```

**`image`** — async image from URL or local path

```elixir
%{type: :image, props: %{
  src:              "https://example.com/photo.jpg",   # URL or local path
  width:            200,
  height:           150,
  content_mode:     :fill,     # :fill | :fit | :stretch
  corner_radius:    8,
  placeholder_color: :gray_200,
}, children: []}
```

iOS uses `AsyncImage` (built-in); Android uses Coil. Both handle URL loading natively.

**`progress`** — linear progress bar

```elixir
# Determinate
%{type: :progress, props: %{value: 0.6, color: :blue_600}, children: []}

# Indeterminate (spinner / animated bar)
%{type: :progress, props: %{indeterminate: true, color: :blue_600}, children: []}
```

**`video`** — local video playback

```elixir
%{type: :video, props: %{
  src:      "/path/to/video.mp4",  # local file path
  autoplay: true,
  loop:     false,
  controls: true,
  width:    360,
  height:   240,
}, children: []}
```

iOS: `AVPlayer` wrapped in `UIViewRepresentable`. Android: `Media3 ExoPlayer`.

### Input

**`button`** — tappable button

```elixir
%{type: :button, props: %{
  text:       "Save",
  background: :blue_600,
  text_color: :white,
  text_size:  :lg,
  padding:    12,
  on_tap:     {self(), :save_tapped},
}, children: []}
```

**`text_field`** — single-line text input

```elixir
%{type: :text_field, props: %{
  value:         assigns.name,
  placeholder:   "Enter name",
  keyboard_type: :default,    # :default | :email | :numeric | :phone | :url
  on_change:     {self(), :name_changed},   # → {:change, :name_changed, "new value"}
  on_focus:      {self(), :name_focus},     # → {:tap, :name_focus}
  on_blur:       {self(), :name_blur},      # → {:tap, :name_blur}
  on_submit:     {self(), :name_submit},    # → {:tap, :name_submit} on Return key
}, children: []}
```

**`toggle`** — on/off switch

```elixir
%{type: :toggle, props: %{
  value:     assigns.enabled,
  on_change: {self(), :toggle_changed},   # → {:change, :toggle_changed, true | false}
}, children: []}
```

**`slider`** — continuous value input

```elixir
%{type: :slider, props: %{
  value:     assigns.volume,
  min:       0.0,
  max:       1.0,
  on_change: {self(), :volume_changed},   # → {:change, :volume_changed, 0.72}
}, children: []}
```

### Lists

**`lazy_list`** — virtualized scrolling list (low-level)

```elixir
%{type: :lazy_list, props: %{
  on_end_reached: {self(), :load_more},   # → {:tap, :load_more}
}, children: rows}    # rows are pre-rendered node maps
```

**`list`** — higher-level list with built-in event routing and default renderer

```elixir
%{type: :list, props: %{
  id:             :items,
  items:          assigns.items,          # raw data
  on_end_reached: {self(), :items},       # → {:end_reached, :items}
}, children: []}
```

Row taps arrive as `{:select, id, index}`. Register a custom renderer at mount time:

```elixir
def mount(_params, _session, socket) do
  socket = Mob.List.put_renderer(socket, :items, &item_row/1)
  {:ok, Mob.Socket.assign(socket, :items, [])}
end

defp item_row(item) do
  %{type: :row, props: %{padding: 12}, children: [
    %{type: :text, props: %{text: item.title}, children: []},
  ]}
end
```

Default renderer handles binaries (shown as text), maps with `:label` / `:title` / `:name` keys, and falls back to `inspect/1`.

### Navigation containers

**`tab_bar`** — bottom tab bar

```elixir
%{type: :tab_bar,
  props: %{
    active:        assigns.active_tab,
    on_tab_select: {self(), :tab_changed},   # → {:change, :tab_changed, "tab_id"}
    tabs: [
      %{id: "home",    label: "Home",    icon: "house"},
      %{id: "profile", label: "Profile", icon: "person"},
    ]
  },
  children: [home_view(assigns), profile_view(assigns)]
}
```

Tab children are rendered in order; the active tab's child is shown. Icons are SF Symbol names (iOS) / text fallback (Android — Material Icons are a future addition).

---

## Styling

### Color tokens

Pass atom color tokens instead of hex values. Tokens are resolved in `Mob.Renderer` before serialisation — zero runtime cost on the native side.

Color scale: `:gray_50` through `:gray_950`, `:red_500`, `:blue_600`, `:green_700`, etc. Full Tailwind 500–950 palette. Special tokens: `:white`, `:black`, `:transparent`, `:primary`, `:on_primary`.

```elixir
%{type: :text, props: %{text: "Hello", text_color: :blue_600, background: :gray_50}, children: []}
```

### Text size tokens

| Token | Approximate size |
|-------|-----------------|
| `:xs` | 12 sp/pt |
| `:sm` | 14 sp/pt |
| `:base` | 16 sp/pt |
| `:lg` | 18 sp/pt |
| `:xl` | 20 sp/pt |
| `"2xl"` | 24 sp/pt |
| `"3xl"` | 30 sp/pt |

### `Mob.Style`

Reusable prop maps that can be shared across components:

```elixir
@card_style %Mob.Style{props: %{background: :white, padding: 16, corner_radius: 8}}

%{type: :column, props: %{style: @card_style, padding_bottom: 8}, children: [...]}
```

Inline props override style values. `Mob.Renderer` merges them before serialisation.

### Per-edge padding

Any layout node accepts individual edge overrides. Missing edges fall back to the uniform `padding` value.

```elixir
%{type: :column, props: %{
  padding:        16,
  padding_top:    trunc(assigns.safe_area.top) + 16,
}, children: [...]}
```

Available edges: `padding_top`, `padding_right`, `padding_bottom`, `padding_left`.

### Platform blocks

Props under an `:ios` or `:android` key are applied only on that platform. The other platform's block is silently dropped by `Mob.Renderer`.

```elixir
%{type: :column, props: %{
  padding: 16,
  ios:     %{background: :gray_50},
  android: %{background: :white},
}, children: [...]}
```

---

## Events

Mob uses two event shapes:

| Shape | When |
|-------|------|
| `{:tap, tag}` | Button press, text field focus/blur/submit, list row tap (via `:select`) |
| `{:change, tag, value}` | Text field text change, toggle flip, slider drag, tab selection |

Both arrive in `handle_info/2`:

```elixir
def handle_info({:tap,    :save_pressed},            socket), do: ...
def handle_info({:change, :name_changed,  new_text}, socket), do: ...
def handle_info({:change, :toggle_on,     true},     socket), do: ...
def handle_info({:change, :volume,        0.72},     socket), do: ...
def handle_info({:select, :items,         2},        socket), do: ...   # list row tap
def handle_info({:end_reached, :items},              socket), do: ...
def handle_info(_message, socket), do: {:noreply, socket}   # always add a catch-all
```

The `tag` in `on_tap: {self(), :tag}` / `on_change: {self(), :tag}` is the atom that appears in the event.

---

## Navigation

Mob has a built-in navigation stack managed inside the screen's GenServer. No separate navigator or router process is needed.

### Basic operations

Navigate from a `handle_event` or `handle_info` by returning a modified socket:

```elixir
# Push a new screen onto the stack
{:noreply, Mob.Socket.push_screen(socket, :detail_screen, %{id: 42})}

# Go back one screen (restores the previous socket state exactly)
{:noreply, Mob.Socket.pop_screen(socket)}

# Go back to a specific screen in the history
{:noreply, Mob.Socket.pop_to(socket, :menu_screen)}

# Go all the way back to the root screen
{:noreply, Mob.Socket.pop_to_root(socket)}

# Replace the entire stack with a fresh screen (no back button)
{:noreply, Mob.Socket.reset_to(socket, :home_screen, %{})}
```

Destinations are registered name atoms (`:detail_screen`) looked up via `Mob.Nav.Registry`, or full module atoms (`MyApp.DetailScreen`) used directly.

### How the stack works

The stack is a list of `{module, socket}` pairs stored in the GenServer state. `push` saves the current screen and mounts the new one. `pop` restores the previous screen's socket exactly as it was — no re-mount. `reset_to` clears the stack entirely and mounts fresh.

### Animated transitions

Set the transition before navigating; the platform UI animates accordingly:

| Transition | Animation |
|------------|-----------|
| `:push` | Slide in from right, old screen exits left |
| `:pop` | Slide in from left, old screen exits right |
| `:reset` | Cross-fade |
| `:none` | Instant (default) |

Mob.Screen sets the transition automatically based on the nav action — push uses `:push`, all pop variants use `:pop`, reset uses `:reset`.

### Hardware back gesture

Both platforms intercept the system back gesture automatically — no code needed in your screens.

- **Android**: the system back gesture (swipe from edge or hardware button) pops the nav stack. At the root screen (stack empty) the app is backgrounded via `moveTaskToBack(true)`.
- **iOS**: a left-edge swipe gesture on the hosting controller pops the nav stack. At the root screen it is a no-op — iOS apps background naturally via the home gesture, which is OS-controlled.

The gesture sends `{:mob, :back}` to the BEAM, which `Mob.Screen` intercepts before your `handle_info`. Your screens don't need to implement anything for this to work.

### Auth flow and the "home screen"

The bottom of the nav stack is the effective home screen — whatever was last passed to `reset_to`. After a successful login, call `reset_to(socket, MainScreen)` to zero the stack. The user can then press back repeatedly and will be backgrounded at the main screen, never returned to the login screen.

```elixir
# In your LoginScreen after successful auth:
{:noreply, Mob.Socket.reset_to(socket, MyApp.HomeScreen)}
```

### Deep links and constructed history

When arriving from a notification or external URL, you want a back stack even though the user didn't navigate there manually. `replace_stack` (planned) will allow constructing an arbitrary history:

```elixir
Mob.Socket.replace_stack(socket, [
  {:home_screen, %{}},
  {:list_screen, %{category: :recent}},
  {:detail_screen, %{id: 42}}   # becomes the active screen
])
```

## Display

### Safe area insets

Every screen automatically receives `assigns.safe_area` — a map with the size of the system-reserved zones in logical points (dp on Android, UIKit points on iOS):

```elixir
assigns.safe_area
# %{top: 62.0, bottom: 34.0, left: 0.0, right: 0.0}
```

| Key | What it covers |
|-----|---------------|
| `top` | Status bar + Dynamic Island / notch |
| `bottom` | Home indicator bar |
| `left` / `right` | Curved-edge insets (most devices: `0.0`) |

Values are `0.0` on devices without those features (older iPhones without a notch, most Androids). You get them for free — no opt-in needed.

**The framework does not insert any padding automatically.** Use the values however you like:

```elixir
def render(assigns) do
  safe_top    = trunc(assigns.safe_area.top)
  safe_bottom = trunc(assigns.safe_area.bottom)

  # Full-bleed header: colour fills behind the Dynamic Island,
  # text sits below it.
  %{type: :column, props: %{background: :blue_700}, children: [
    %{type: :spacer, props: %{size: safe_top}, children: []},
    %{type: :text,   props: %{text: "My App", padding: 16, ...}, children: []}
  ]}
end
```

Or add a plain spacer at the top and bottom of your scroll content if you just want the text to clear the system chrome.

## Live debugging

Mob supports full Erlang distribution so you can inspect and hot-push code to a running app without rebuilding.

### Setup

Add to your app's `start/0`:

```elixir
Mob.Dist.ensure_started(node: :"my_app@127.0.0.1", cookie: :my_cookie)
```

On iOS, distribution is started at BEAM launch via flags in `mob_beam.m`. On Android, `Mob.Dist` defers startup by 3 seconds to avoid a race with Android's hwui thread pool.

### Connect

Two named sessions are the standard: one for interactive use, one for agent/automated tasks.

```bash
# iOS simulator (no port forwarding needed)
./dev_connect.sh ios user
./dev_connect.sh ios agent

# Android emulator (sets up adb port forwarding automatically)
./dev_connect.sh android user
./dev_connect.sh android agent
```

Both connect to `mob_demo@127.0.0.1` with cookie `mob_secret`.

### What you can do once connected

```elixir
Node.list()   # confirm device node is visible

# Inspect live screen state
pid = :rpc.call(:"mob_demo@127.0.0.1", :erlang, :list_to_pid, [~c"<0.92.0>"])
:rpc.call(:"mob_demo@127.0.0.1", Mob.Screen, :get_socket, [pid])

# Hot-push a changed module (no rebuild needed)
mix compile && nl(MyApp.CounterScreen)
```

### EPMD tunneling

iOS simulator shares the Mac's network stack — no port setup needed.

Android uses `adb reverse tcp:4369 tcp:4369` so the Android BEAM registers in the Mac's
EPMD (not Android's), then `adb forward tcp:9100 tcp:9100` for the dist port. Both
platforms end up in the same EPMD. `dev_connect.sh` handles this automatically.

## Android manifest requirements

Your Android `AndroidManifest.xml` needs a few specific settings for Mob to work
correctly. These are already included in projects created with `mix mob.new`, but if
you're integrating Mob into an existing Android project, add them manually.

### windowSoftInputMode

Without this, tapping a `text_field` component does **not** raise the soft keyboard —
Android defaults to overlaying the keyboard on top of the window instead of resizing it.

```xml
<activity
    android:name=".MainActivity"
    android:windowSoftInputMode="adjustResize"
    ...>
```

### configChanges

Without `android:configChanges`, Android recreates the `Activity` on orientation
changes, keyboard appearance, and other config events. This causes `nativeStartBeam()`
to be called a second time, crashing the already-running BEAM.

```xml
<activity
    android:name=".MainActivity"
    android:configChanges="orientation|screenSize|screenLayout|keyboard|keyboardHidden|navigation|uiMode|fontScale|density"
    ...>
```

### AppTheme with black windowBackground

The default Android theme has a white window background. When the app resumes or the
surface is recreated, there is a 1–2 frame gap before Compose draws its first frame.
Without overriding the background, this gap shows as a white flash.

Create `res/values/styles.xml`:

```xml
<resources>
    <style name="AppTheme" parent="android:style/Theme.NoTitleBar">
        <item name="android:windowBackground">@android:color/black</item>
        <item name="android:windowAnimationStyle">@null</item>
        <item name="android:windowNoTitle">true</item>
    </style>
</resources>
```

Then reference it in your manifest:

```xml
<application
    android:theme="@style/AppTheme"
    ...>
```

### Complete activity element example

```xml
<application android:theme="@style/AppTheme" ...>
    <activity
        android:name=".MainActivity"
        android:exported="true"
        android:windowSoftInputMode="adjustResize"
        android:configChanges="orientation|screenSize|screenLayout|keyboard|keyboardHidden|navigation|uiMode|fontScale|density">
        <intent-filter>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent-filter>
    </activity>
</application>
```

## OS debug tools

If you're coming from Elixir/backend land, the mobile toolchains have their own CLIs for talking to devices. Here's what's useful and what each thing does.

### Android — adb

`adb` (Android Debug Bridge) is the main CLI for talking to Android devices and emulators. It ships with Android Studio but you can also install it standalone (`brew install android-platform-tools`).

```bash
adb devices                          # list connected devices/emulators
adb -s emulator-5554 shell           # open a shell on a specific device
```

**Logs** — the equivalent of `tail -f` on your app's output:

```bash
adb logcat                           # everything (very noisy)
adb logcat -s Elixir                 # only Logger output from your BEAM code
adb logcat -s Elixir MobBeam MobNIF  # BEAM + native bridge logs
adb logcat -v time -s Elixir,MobBeam,MobNIF  # same, with timestamps
```

**File transfer:**

```bash
adb push local/path /data/local/tmp/file   # Mac → device
adb pull /data/local/tmp/file local/path   # device → Mac
```

**Port forwarding** — needed to connect Erlang distribution between Mac and Android emulator:

```bash
adb reverse tcp:4369 tcp:4369   # EPMD: Android BEAM registers in Mac's EPMD
adb forward tcp:9100 tcp:9100   # dist port: Mac can reach Android node
```

`mix mob.connect` runs these automatically.

**App lifecycle:**

```bash
adb shell am force-stop com.mob.demo        # kill the app entirely
adb shell input keyevent KEYCODE_HOME       # press home button (backgrounds app)
adb shell am start -n com.mob.demo/.MainActivity  # launch app
adb install path/to/app.apk                 # install an APK
```

**Battery info** (used by `mix mob.battery_bench`):

```bash
adb shell dumpsys battery                   # current battery state
adb shell dumpsys batterystats | grep "Charge counter"  # mAh counter
```

**Wireless ADB** — cut the USB cable once set up:

```bash
# While plugged in via USB:
adb -s SERIAL tcpip 5555             # switch device to TCP mode
adb connect 192.168.1.42:5555        # connect over WiFi
adb devices                          # confirm it shows up
```

### iOS — xcrun simctl

`xcrun simctl` is the CLI for the iOS Simulator. It's part of Xcode command-line tools (`xcode-select --install`).

```bash
xcrun simctl list devices            # list all simulators and their UDIDs
xcrun simctl list devices booted     # only the ones currently running
```

**Boot and open a simulator:**

```bash
xcrun simctl boot <UDID>                    # boot without opening the window
open -a Simulator                           # open the Simulator app window
```

**Logs** — streams NSLog / os_log output from your app:

```bash
xcrun simctl spawn booted log stream \
  --predicate 'process == "MobDemo"'        # only MobDemo output

# Save to file for later inspection:
xcrun simctl spawn booted log stream \
  --predicate 'process == "MobDemo"' > /tmp/mob.log &
```

**App lifecycle:**

```bash
xcrun simctl launch booted com.mob.demo     # launch app
xcrun simctl terminate booted com.mob.demo  # kill app (simulates backgrounding / force-quit)
xcrun simctl install booted path/to/App.app # install a built .app bundle
```

**Find app's data directory** (useful for reading crash dumps, finding BEAM files):

```bash
xcrun simctl get_app_container booted com.mob.demo data
# → /Users/you/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/...
```

**Privacy / permissions reset** (helpful when testing first-run flows):

```bash
xcrun simctl privacy booted reset all com.mob.demo
```

### Backgrounding the app from Elixir

Both platforms expose `Mob.Socket.exit_app/1` (planned) or you can call the NIF directly from IEx:

```elixir
# From an IEx session connected to the device:
:rpc.call(:"mob_demo_android@127.0.0.1", :mob_nif, :exit_app, [])
# Android: calls moveTaskToBack(true) — app goes to background, BEAM keeps running
# iOS: no-op — iOS apps background via the home gesture, which is OS-controlled
```

## Power benchmark

The BEAM's idle power draw on a real Android device is negligible when tuned correctly.
Use `mix mob.battery_bench` (from `mob_dev`) to measure battery drain for your app.

### Running a benchmark

```bash
# WiFi ADB setup (once, while plugged in):
adb -s SERIAL tcpip 5555
adb connect PHONE_IP:5555

# Run with defaults (Nerves-tuned BEAM, 30 min):
mix mob.battery_bench --device 192.168.1.42:5555

# Compare against no-BEAM baseline:
mix mob.battery_bench --no-beam --device 192.168.1.42:5555

# Try a specific preset:
mix mob.battery_bench --preset untuned   # raw BEAM, no tuning
mix mob.battery_bench --preset sbwt      # busy-wait disabled only
mix mob.battery_bench --preset nerves    # full Nerves set (same as default)

# Custom flags:
mix mob.battery_bench --flags "-sbwt none -S 1:1"

# Longer run for more accurate mAh resolution:
mix mob.battery_bench --duration 3600
```

### What the results mean

Example results on a Moto G phone (30-min screen-off run):

| Config          | mAh drain | mAh/hr |
|-----------------|-----------|--------|
| no-beam         | 100 mAh   | 200    |
| nerves (default)| 101 mAh   | 202    |
| untuned BEAM    | 125 mAh   | 250    |

The Nerves-tuned BEAM (`-S 1:1 -sbwt none +C multi_time_warp`) has essentially the same
idle power draw as a stock Android app. The overhead is in the noise for most workloads.
The untuned BEAM uses ~25% more power due to scheduler busy-waiting.

### Tuning flags

| Flag | Effect |
|------|--------|
| `-S 1:1 -SDcpu 1:1 -SDio 1` | Single scheduler — no cross-CPU wakeups |
| `-A 1` | Single async thread pool thread |
| `-sbwt none -sbwtdcpu none -sbwtdio none` | Disable busy-wait in all schedulers |
| `+C multi_time_warp` | Allow clock to jump forward; avoids spurious wakeups |

## Device capabilities

Hardware APIs follow the same `handle_info` convention as UI events. Capabilities that need OS permission use `Mob.Permissions.request/2` — the result arrives as `handle_info`.

### Permissions

```elixir
# Request a permission (shows OS dialog if not already decided)
{:noreply, Mob.Permissions.request(socket, :camera)}

# Arrives as:
def handle_info({:permission, :camera, :granted}, socket), do: ...
def handle_info({:permission, :camera, :denied},  socket), do: ...
```

Capabilities that require permissions: `:camera`, `:microphone`, `:photo_library`, `:location`, `:notifications`.

Capabilities that need no permission: haptics, clipboard, share sheet, file picker (user-initiated).

### Haptics

```elixir
Mob.Haptic.trigger(socket, :light)    # brief tap
Mob.Haptic.trigger(socket, :medium)   # standard tap
Mob.Haptic.trigger(socket, :heavy)    # strong tap
Mob.Haptic.trigger(socket, :success)  # success pattern
Mob.Haptic.trigger(socket, :error)    # error pattern
Mob.Haptic.trigger(socket, :warning)  # warning pattern
```

Returns the socket unchanged so it can be used inline. Fire-and-forget.

### Clipboard

```elixir
# Write to clipboard
Mob.Clipboard.put(socket, "some text")

# Read from clipboard (synchronous)
case Mob.Clipboard.get(socket) do
  {:clipboard, :ok, text} -> ...
  {:clipboard, :empty}    -> ...
end
```

### Share sheet

Opens the OS share dialog. Fire-and-forget.

```elixir
Mob.Share.text(socket, "Check out Mob!")
```

### Biometric authentication

```elixir
# Requires no extra permission — uses device unlock credentials
Mob.Biometric.authenticate(socket, reason: "Confirm payment")

def handle_info({:biometric, :success},       socket), do: ...
def handle_info({:biometric, :failure},        socket), do: ...
def handle_info({:biometric, :not_available},  socket), do: ...
```

iOS: `LAContext.evaluatePolicy` (Face ID / Touch ID). Android: `BiometricPrompt`.

### Location

```elixir
# One-shot fix (requires :location permission)
Mob.Location.get_once(socket)

# Continuous updates
Mob.Location.start(socket, accuracy: :high)
Mob.Location.stop(socket)

def handle_info({:location, %{lat: lat, lon: lon, accuracy: acc, altitude: alt}}, socket), do: ...
def handle_info({:location, :error, reason}, socket), do: ...
```

Accuracy levels: `:high` (GPS), `:balanced`, `:low` (cell/WiFi only).

iOS: `CLLocationManager`. Android: `FusedLocationProviderClient`.

Permission key: `:location`.

### Camera

```elixir
# Capture a photo (opens native camera UI)
Mob.Camera.capture_photo(socket, quality: :high)

# Capture a video
Mob.Camera.capture_video(socket, max_duration: 60)

def handle_info({:camera, :photo, %{path: path, width: w, height: h}}, socket), do: ...
def handle_info({:camera, :video, %{path: path, duration: secs}},       socket), do: ...
def handle_info({:camera, :cancelled},                                   socket), do: ...
```

iOS: `UIImagePickerController`. Android: `TakePicture` / `TakeVideo` activity contracts.

Permission key: `:camera` (and `:microphone` for video).

### Photo library picker

```elixir
Mob.Photos.pick(socket, max: 3, types: [:image, :video])

def handle_info({:photos, :picked,    items},   socket), do: ...
def handle_info({:photos, :cancelled},          socket), do: ...
# items: [%{path: ..., type: :image | :video, width: ..., height: ...}]
```

iOS: `PHPickerViewController` (no permission needed on iOS 14+). Android: `PickMultipleVisualMedia`.

### File picker

```elixir
Mob.Files.pick(socket, types: ["application/pdf", "text/plain"])

def handle_info({:files, :picked,    items},   socket), do: ...
def handle_info({:files, :cancelled},          socket), do: ...
# items: [%{path: ..., name: ..., mime: ..., size: ...}]
```

iOS: `UIDocumentPickerViewController`. Android: `OpenMultipleDocuments`.

### Microphone / audio recording

```elixir
# Requires :microphone permission
Mob.Audio.start_recording(socket, format: :aac, quality: :medium)
Mob.Audio.stop_recording(socket)

def handle_info({:audio, :recorded, %{path: path, duration: secs}}, socket), do: ...
def handle_info({:audio, :error,    reason},                          socket), do: ...
```

Formats: `:aac` (default), `:wav`. Quality: `:low`, `:medium` (default), `:high`.

iOS: `AVAudioRecorder`. Android: `MediaRecorder`.

### Accelerometer / gyroscope

```elixir
# No permission required
Mob.Motion.start(socket, sensors: [:accelerometer, :gyro], interval_ms: 100)
Mob.Motion.stop(socket)

def handle_info({:motion, %{accel: {ax, ay, az}, gyro: {gx, gy, gz}, timestamp: t}}, socket), do: ...
```

Omit `:gyro` to get accelerometer only; omit `:accelerometer` for gyro only.

iOS: `CMMotionManager`. Android: `SensorManager`.

### QR / barcode scanner

```elixir
# Requires :camera permission
Mob.Scanner.scan(socket, formats: [:qr, :ean13, :code128])

def handle_info({:scan, :result,    %{type: :qr, value: "https://..."}}, socket), do: ...
def handle_info({:scan, :cancelled},                                       socket), do: ...
```

Supported formats: `:qr`, `:ean13`, `:ean8`, `:code128`, `:code39`, `:upca`, `:upce`, `:pdf417`, `:aztec`, `:data_matrix`.

iOS: `AVCaptureMetadataOutput` + `AVFoundation`. Android: `CameraX` + ML Kit `BarcodeScanning`.

### Notifications

Notifications always arrive via `handle_info`, whether the app is foregrounded, backgrounded, or relaunched after being killed. When the app is killed and the user taps a notification, the BEAM starts normally, `mount/3` runs, and then the notification is delivered to `handle_info` — no special `mount` case needed.

**Local notifications** (scheduled by your app, no server):

```elixir
# Request permission first
Mob.Permissions.request(socket, :notifications)

# Schedule a notification
Mob.Notify.schedule(socket,
  id:    "reminder_1",
  title: "Time to check in",
  body:  "Open the app to see today's updates",
  at:    ~U[2026-04-16 09:00:00Z],   # or delay_seconds: 60
  data:  %{screen: "reminders"}
)

# Cancel a pending notification
Mob.Notify.cancel(socket, "reminder_1")

# Arrival (foreground, background tap, or launch tap):
def handle_info({:notification, %{id: id, data: data, source: :local}}, socket), do: ...
```

**Push notifications** (`mob_push` package, separate from core `mob`):

```elixir
# Register for push (call once at app start after permission granted)
Mob.Notify.register_push(socket)

# Token arrives — send it to your server
def handle_info({:push_token, :ios,     token}, socket), do: ...
def handle_info({:push_token, :android, token}, socket), do: ...

# Incoming push:
def handle_info({:notification, %{title: t, body: b, data: d, source: :push}}, socket), do: ...
```

iOS: `UNUserNotificationCenter` + APNs. Android: `NotificationManager` + `AlarmManager` + FCM.

The `mob_push` server-side library (separate Hex package) handles sending to FCM / APNs:

```elixir
# In your Phoenix/Elixir server:
MobPush.send(token, :ios,     %{title: "Hi", body: "Hello", data: %{}})
MobPush.send(token, :android, %{title: "Hi", body: "Hello", data: %{}})
```

---

## Source

[github.com/genericjam/mob](https://github.com/genericjam/mob)
