# Device Capabilities

All device APIs in Dala follow a consistent pattern: call the function from a callback (returning the socket unchanged), then handle the result in `handle_info/2`. APIs never block the screen process.

## Permissions

Some capabilities require an OS permission before they can be used. Request permissions via `Dala.Permissions.request/2`. The result arrives asynchronously:

```elixir
def mount(_params, _session, socket) do
  socket = Dala.Permissions.request(socket, :camera)
  {:ok, socket}
end

def handle_info({:permission, :camera, :granted}, socket) do
  {:noreply, Dala.Socket.assign(socket, :camera_ready, true)}
end

def handle_info({:permission, :camera, :denied}, socket) do
  {:noreply, Dala.Socket.assign(socket, :camera_ready, false)}
end
```

**Capabilities that require permission:** `:camera`, `:microphone`, `:photo_library`, `:location`, `:notifications`

**No permission needed:** haptics, clipboard, share sheet, file picker.

## Haptic feedback

`Dala.Haptic.trigger/2` fires synchronously (no `handle_info` needed) and returns the socket:

```elixir
def handle_event("tap", %{"tag" => "purchase"}, socket) do
  socket = Dala.Haptic.trigger(socket, :success)
  {:noreply, socket}
end
```

Feedback types: `:light`, `:medium`, `:heavy`, `:success`, `:error`, `:warning`

iOS uses `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`. Android uses `View.performHapticFeedback`.

## Clipboard

```elixir
# Write to clipboard
def handle_event("tap", %{"tag" => "copy"}, socket) do
  socket = Dala.Clipboard.write(socket, socket.assigns.code)
  {:noreply, socket}
end

# Read from clipboard — result arrives in handle_info
def handle_event("tap", %{"tag" => "paste"}, socket) do
  socket = Dala.Clipboard.read(socket)
  {:noreply, socket}
end

def handle_info({:clipboard, :read, text}, socket) do
  {:noreply, Dala.Socket.assign(socket, :pasted_text, text)}
end
```

## Share sheet

Opens the platform's native share sheet (iOS: `UIActivityViewController`, Android: `ACTION_SEND`):

```elixir
def handle_event("tap", %{"tag" => "share"}, socket) do
  socket = Dala.Share.sheet(socket, text: "Check out this app!", url: "https://example.com")
  {:noreply, socket}
end
```

Options: `:text`, `:url`, `:title`

## Camera

Requires `:camera` permission (and `:microphone` for video).

```elixir
# Capture a photo
socket = Dala.Camera.capture_photo(socket)
socket = Dala.Camera.capture_photo(socket, quality: :medium)

# Record a video
socket = Dala.Camera.capture_video(socket)
socket = Dala.Camera.capture_video(socket, max_duration: 30)

# Results:
def handle_info({:camera, :photo, %{path: path, width: w, height: h}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :photo_path, path)}
end

def handle_info({:camera, :video, %{path: path, duration: seconds}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :video_path, path)}
end

def handle_info({:camera, :cancelled}, socket) do
  {:noreply, socket}
end
```

`path` is a local temp file. Copy it to a permanent location before the next capture.

## Photos

Browse and pick from the photo library. Requires `:photo_library` permission.

```elixir
socket = Dala.Photos.pick(socket)
socket = Dala.Photos.pick(socket, max: 5)  # pick up to 5

def handle_info({:photos, :picked, photos}, socket) do
  # photos is a list of %{path: path, width: w, height: h} maps
  {:noreply, Dala.Socket.assign(socket, :photos, photos)}
end

def handle_info({:photos, :cancelled}, socket) do
  {:noreply, socket}
end
```

## Files

Open the system file picker:

```elixir
socket = Dala.Files.pick(socket)
socket = Dala.Files.pick(socket, types: ["public.pdf", "public.text"])  # iOS UTI strings
socket = Dala.Files.pick(socket, types: ["application/pdf", "text/plain"])  # Android MIME types

def handle_info({:files, :picked, files}, socket) do
  # files is a list of %{path: path, name: name, size: bytes} maps
  {:noreply, Dala.Socket.assign(socket, :files, files)}
end
```

> **Platform note:** `types` uses iOS UTI strings on iOS (`"public.pdf"`) and MIME type strings on Android (`"application/pdf"`). To support both platforms with the same call, pass both forms — the platform ignores strings it doesn't recognise. See [Platform-specific props](components.md#platform-specific-props) for a cleaner pattern.
```

## Camera preview

Display a live camera feed inline (no OS permission dialog for preview):

```elixir
def mount(_params, _session, socket) do
  socket = Dala.Camera.start_preview(socket, facing: :back)
  {:ok, socket}
end

def render(assigns) do
  ~dala"""
  <Column>
    <CameraPreview facing={:back} weight={1} />
    <Button text="Flip" on_tap={{self(), :flip}} />
  </Column>
  """
end

def terminate(_reason, socket) do
  Dala.Camera.stop_preview(socket)
  :ok
end
```

The `:camera_preview` component requires an active preview session — call `start_preview/2` before mounting and `stop_preview/1` in `terminate/2`.

## Audio recording

Requires `:microphone` permission.

```elixir
socket = Dala.Audio.start_recording(socket)
socket = Dala.Audio.start_recording(socket, format: :aac, quality: :medium)
socket = Dala.Audio.stop_recording(socket)

def handle_info({:audio, :recorded, %{path: path, duration: seconds}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :recording, path)}
end

def handle_info({:audio, :error, reason}, socket) do
  {:noreply, Dala.Socket.assign(socket, :error, reason)}
end
```

Recording formats: `:aac` (default), `:wav`. Quality: `:low`, `:medium` (default), `:high`.

## Audio playback

No permission needed. Plays local files or remote URLs.

```elixir
socket = Dala.Audio.play(socket, "/path/to/clip.m4a")
socket = Dala.Audio.play(socket, path, loop: true, volume: 0.8)
socket = Dala.Audio.stop_playback(socket)
socket = Dala.Audio.set_volume(socket, 0.5)  # adjust without stopping

def handle_info({:audio, :playback_finished, %{path: path}}, socket) do
  {:noreply, socket}
end

def handle_info({:audio, :playback_error, %{reason: reason}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :error, reason)}
end
```

iOS uses `AVAudioPlayer` / `AVPlayer`. Android uses `MediaPlayer`.

## Location

Requires `:location` permission.

```elixir
# Single fix
socket = Dala.Location.get_once(socket)

# Continuous updates
socket = Dala.Location.start(socket)
socket = Dala.Location.start(socket, accuracy: :high)  # :high | :balanced | :low
socket = Dala.Location.stop(socket)

def handle_info({:location, %{lat: lat, lon: lon, accuracy: acc, altitude: alt}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :location, %{lat: lat, lon: lon})}
end

def handle_info({:location, :error, reason}, socket) do
  {:noreply, Dala.Socket.assign(socket, :location_error, reason)}
end
```

iOS uses `CLLocationManager`. Android uses `FusedLocationProviderClient`.

## Motion (accelerometer / gyroscope)

```elixir
socket = Dala.Motion.start(socket)
socket = Dala.Motion.start(socket, interval_ms: 100)
socket = Dala.Motion.stop(socket)

def handle_info({:motion, %{ax: ax, ay: ay, az: az, gx: gx, gy: gy, gz: gz}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :motion, %{ax: ax, ay: ay, az: az})}
end
```

## Biometric authentication

```elixir
socket = Dala.Biometric.authenticate(socket, reason: "Confirm your identity")

def handle_info({:biometric, :success}, socket) do
  {:noreply, Dala.Socket.assign(socket, :authenticated, true)}
end

def handle_info({:biometric, :failure, reason}, socket) do
  {:noreply, socket}
end
```

iOS uses Face ID / Touch ID. Android uses `BiometricPrompt`.

## QR / barcode scanner

```elixir
socket = Dala.Scanner.scan(socket)

def handle_info({:scan, :result, %{type: type, value: value}}, socket) do
  # type: :qr | :ean | :upc | etc.
  {:noreply, Dala.Socket.assign(socket, :scanned, value)}
end

def handle_info({:scan, :cancelled}, socket) do
  {:noreply, socket}
end
```

## Notifications

See also [Dala.Notify](Dala.Notify.html) for the full API.

Requires `:notifications` permission.

### Local notifications

```elixir
# Schedule
Dala.Notify.schedule(socket,
  id:    "reminder_1",
  title: "Time to check in",
  body:  "Open the app to see today's updates",
  at:    ~U[2026-04-16 09:00:00Z],   # or delay_seconds: 60
  data:  %{screen: "reminders"}
)

# Cancel
Dala.Notify.cancel(socket, "reminder_1")

# Receive in handle_info (all app states: foreground, background, relaunched):
def handle_info({:notification, %{id: id, data: data, source: :local}}, socket) do
  {:noreply, socket}
end
```

### Push notifications

Register for push tokens and forward them to your server. A server-side push library (`dala_push`) is in development.

#### Server credentials

**Apple (APNs) — token-based auth (recommended)**

Create a signing key at:
https://developer.apple.com/account/resources/authkeys/add

Enable "Apple Push Notifications service (APNs)", download the `.p8` file, and note
the Key ID shown in the portal. One key works across all your apps, both development
and production environments, and never expires (but can be revoked if compromised).

You need four things server-side:
- `.p8` key file — downloaded when you create the key (only shown once)
- Key ID — https://developer.apple.com/account/resources/authkeys/list
- Team ID — https://developer.apple.com/account (Membership Details section)
- Bundle ID — https://developer.apple.com/account/resources/identifiers/list

Your server signs a short-lived JWT from these at send time; there is no separate
token to store. See the APNs documentation for the JWT format.

**Google (FCM)**

Create a Firebase project, then: Project Settings → Service accounts →
Generate new private key. Drop `google-services.json` into `android/app/` for
the Android client.

```elixir
# After :notifications permission is granted:
Dala.Notify.register_push(socket)

# Receive the device token:
def handle_info({:push_token, :ios,     token}, socket) do
  MyApp.Server.register_token(:ios, token)
  {:noreply, socket}
end

def handle_info({:push_token, :android, token}, socket) do
  MyApp.Server.register_token(:android, token)
  {:noreply, socket}
end

# Receive push notifications:
def handle_info({:notification, %{title: t, body: b, data: d, source: :push}}, socket) do
  {:noreply, socket}
end
```

## Storage

App-local file storage using named locations instead of raw paths. No permission needed.

```elixir
# Resolve a location to its absolute path
path = Dala.Storage.dir(:documents)   # persists, user-visible on iOS
path = Dala.Storage.dir(:cache)       # persists until OS needs space
path = Dala.Storage.dir(:temp)        # ephemeral, may be purged any time
path = Dala.Storage.dir(:app_support) # persists, hidden from user, backed up on iOS

# File operations
{:ok, files} = Dala.Storage.list(:documents)       # returns full paths
{:ok, meta}  = Dala.Storage.stat("/path/to/file")  # %{name, path, size, modified_at}
{:ok, path}  = Dala.Storage.write("/path/file.txt", "contents")
{:ok, data}  = Dala.Storage.read("/path/file.txt")
{:ok, dest}  = Dala.Storage.copy("/path/src.txt", :documents)  # keeps basename
{:ok, dest}  = Dala.Storage.move("/path/src.txt", "/path/dest.txt")
:ok          = Dala.Storage.delete("/path/file.txt")

ext = Dala.Storage.extension("/tmp/clip.mp4")  # => ".mp4"
```

All operations that can fail return `{:ok, value} | {:error, posix}`. `dir/1` raises on an unknown location atom.

For saving to the native media library (Camera Roll, Downloads), see `Dala.Storage.Apple` and `Dala.Storage.Android`.

## WebView

Embed a native web view and communicate with it over a JS bridge. No permission needed.

```elixir
def render(assigns) do
  ~dala"""
  <WebView url="https://example.com" allow={["https://example.com"]} show_url={true} weight={1} />
  """
end

# Send a message to Elixir from JS:
#   window.dala.send({ event: "clicked", id: 42 })
def handle_info({:webview, :message, %{"event" => "clicked", "id" => id}}, socket) do
  {:noreply, socket}
end

# A navigation attempt was blocked by the allow: whitelist
def handle_info({:webview, :blocked, url}, socket) do
  {:noreply, socket}
end
```

### Programmatic WebView control with `interact/2`

`Dala.WebView.interact/2` provides a high-level API for driving WebView content from Elixir, similar to `Dala.Test` but for production use.

```elixir
def handle_event("submit", _, socket) do
  # Tap an element by CSS selector
  socket = Dala.WebView.interact(socket, {:tap, ".submit-button"})
  {:noreply, socket}
end

def handle_event("fill_form", _, socket) do
  # Type text into an input field
  socket = Dala.WebView.interact(socket, {:type, "#name", "John Doe"})
  {:noreply, socket}
end

def handle_event("clear_input", _, socket) do
  # Clear an input field
  socket = Dala.WebView.interact(socket, {:clear, "#name"})
  {:noreply, socket}
end

def handle_event("eval_js", _, socket) do
  # Evaluate JS and get result via handle_info
  socket = Dala.WebView.interact(socket, {:eval, "document.title"})
  {:noreply, socket}
end

def handle_event("scroll_content", _, socket) do
  # Scroll an element programmatically
  socket = Dala.WebView.interact(socket, {:scroll, ".content", 0, 100})
  {:noreply, socket}
end

def handle_event("wait_for_element", _, socket) do
  # Wait for an element to appear (with timeout in ms)
  socket = Dala.WebView.interact(socket, {:wait, ".loaded", 5000})
  {:noreply, socket}
end

# Results arrive as:
def handle_info({:webview, :interact_result, %{"action" => action, "success" => success}}, socket) do
  {:noreply, socket}
end
```

Available actions:

| Action | Format | Description |
|--------|--------|-------------|
| Tap | `{:tap, selector}` | Tap an element by CSS selector |
| Type | `{:type, selector, text}` | Type text into input fields |
| Clear | `{:clear, selector}` | Clear input fields |
| Eval | `{:eval, js_code}` | Evaluate JS and get result via `handle_info({:webview, :interact_result, ...})` |
| Scroll | `{:scroll, selector, dx, dy}` | Scroll elements programmatically |
| Wait | `{:wait, selector, timeout_ms}` | Wait for elements to appear |

Also available: `Dala.WebView.navigate/2`, `Dala.WebView.reload/1`, `Dala.WebView.stop_loading/1`, `Dala.WebView.go_forward/1` for complete WebView navigation control.

Push a message from Elixir into the page (calls `window.dala.onMessage` handlers):

```elixir
socket = Dala.WebView.post_message(socket, %{type: "update", value: 42})
```

Evaluate arbitrary JavaScript and receive the result:

```elixir
socket = Dala.WebView.eval_js(socket, "document.title")
# Result arrives as:
def handle_info({:webview, :eval_result, result}, socket) do
  {:noreply, socket}
end
```

Props: `:url` (required), `:allow` (list of URL prefixes — blocks others), `:show_url` (native URL bar), `:title` (static label overriding `:show_url`), `:width`, `:height`.

> **Platform note:** WebView is supported on both iOS and Android.

## Alerts and toasts

`Dala.Alert` shows native dialogs and status messages. No permission needed.

### Alert dialog

Centered modal for confirmations and errors (iOS: `UIAlertController(.alert)`, Android: `AlertDialog`).

```elixir
def handle_info({:tap, :delete}, socket) do
  Dala.Alert.alert(socket,
    title:   "Delete item?",
    message: "This cannot be undone.",
    buttons: [
      [label: "Delete", style: :destructive, action: :confirmed_delete],
      [label: "Cancel", style: :cancel]
    ]
  )
  {:noreply, socket}
end

def handle_info({:alert, :confirmed_delete}, socket) do
  {:noreply, do_delete(socket)}
end

def handle_info({:alert, :dismiss}, socket) do
  {:noreply, socket}
end
```

Dismissing without tapping a button (e.g. Android back gesture) sends `{:alert, :dismiss}`.

### Action sheet

Bottom-anchored list for choosing between actions (iOS: `UIAlertController(.actionSheet)`, Android: list dialog).

```elixir
Dala.Alert.action_sheet(socket,
  title:   "Share photo",
  buttons: [
    [label: "Save to Photos", action: :save],
    [label: "Copy link",      action: :copy],
    [label: "Cancel",         style: :cancel]
  ]
)

def handle_info({:alert, :save}, socket), do: {:noreply, save_photo(socket)}
def handle_info({:alert, :copy}, socket), do: {:noreply, copy_link(socket)}
def handle_info({:alert, :dismiss}, socket), do: {:noreply, socket}
```

### Toast

Ephemeral status message with no callback.

```elixir
Dala.Alert.toast(socket, "Saved!")
Dala.Alert.toast(socket, "File uploaded", duration: :long)
```

Duration: `:short` (default, ~2 s) or `:long` (~4 s). iOS renders a floating label overlay; Android uses `Toast`.

### Button options

| Key | Values | Default |
|-----|--------|---------|
| `:label` | string | `""` |
| `:style` | `:default`, `:cancel`, `:destructive` | `:default` |
| `:action` | atom — delivered as `{:alert, atom}` to `handle_info/2` | `:dismiss` |
```
