# Plugin Architecture

Dala is designed as a **runtime-extensible UI host** where everything is just schema + commands + native capabilities. This is the same fundamental direction used by React Native Fabric, Flutter Engine, SwiftUI internals, Jetpack Compose runtime, VSCode extension host, and browser DOM.

## Core Philosophy

Dala core knows almost nothing. Plugins self-describe themselves through:

- **Schema** - component metadata (props, events, capabilities)
- **Commands** - binary protocol for communication
- **Native capabilities** - platform-specific rendering

### What Dala Core Knows

| Thing | Responsibility |
|-------|----------------|
| Tree | UI node graph |
| Diff engine | updates |
| Binary transport | commands |
| Scheduler | async/state |
| Registry | plugin lookup |
| Layout protocol | sizing/constraints |
| Event bridge | event routing |

Everything else — video, maps, charts, camera, ML view, custom renderer, AR, Metal canvas — becomes plugins.

## The Plugin Lifecycle

### 1. Self-Describing Component Schema

Plugins declare themselves declaratively:

```elixir
defmodule MyApp.VideoPlugin do
  use Dala.Plugin

  component "video" do
    prop "source", :string
    prop "autoplay", :bool
    prop "controls", :bool
    prop "volume", :f32

    event "progress"
    event "ended"

    native "ios", "DalaVideoView"
    native "android", "com.dala.video.VideoView"

    capability :gestures
    capability :accessibility
    capability :animation
  end
end
```

This is NOT UI code. This is metadata.

Core Dala automatically generates:

- Protocol encoders/decoders
- Validators
- Documentation
- Registry entries

### 2. Universal Node Model

Everything becomes a generic node:

```elixir
%Dala.Node{
  type: "video",
  props: %{source: "...", autoplay: true},
  children: []
}
```

Dala core NEVER special-cases video, maps, or charts. The same generic lifecycle applies to all plugins:

- `create/2`
- `update/2`
- `layout/2`
- `event/3`
- `dispose/1`

Optional capabilities:

- `animate/2`
- `focus/2`
- `accessibility/2`
- `snapshot/1`
- `texture/1`
- `gesture/2`

### 3. Universal Command Stream

Dala core emits only generic operations:

- `CREATE_NODE`
- `UPDATE_PROP`
- `REMOVE_NODE`
- `EMIT_EVENT`
- `RUN_ANIMATION`

Plugins interpret semantics. Core stays tiny.

### 4. Versioned Schema ABI

Plugins MUST declare versions for compatibility:

```elixir
schema_version "1.0.0"
protocol_version 3
native_api_version "2.0.0"
```

Otherwise ecosystem explodes later.

### 5. Host/Runtime Separation

Plugins should NEVER directly access:

- BEAM internals
- Scheduler state
- Raw protocol sockets

Instead:

```
Plugin
   ↓
Host API
   ↓
Dala Runtime
```

Exactly like browser extensions.

## Schema-First Architecture

Designing around **schema-first** (not widget-first, not native-view-first, not protocol-first) unlocks:

- Tooling and validation
- Code generation
- Compatibility guarantees
- Visual editors
- Plugin ecosystems
- AI-generated UIs
- Hot reload
- Documentation

## Plugin Package Structure

```
my_plugin/
 ├── lib/
 │    └── my_plugin.ex          # Plugin schema definitions
 ├── native/
 │    ├── rust/                 # Rust NIF extensions (optional)
 │    ├── ios/                  # iOS native views
 │    └── android/              # Android native views
 ├── protocol/                  # Generated binary protocol
 └── assets/                    # Static assets
```

## Defining a Plugin

### Basic Structure

```elixir
defmodule MyApp.MyPlugin do
  use Dala.Plugin,
    schema_version: "1.0.0",
    protocol_version: 3,
    native_api_version: "2.0.0"

  component "my_component" do
    # Define properties
    prop "title", :string, required: true
    prop "count", :integer, default: 0
    prop "enabled", :bool, default: false

    # Define events
    event "clicked"
    event "changed", payload: %{value: :integer}

    # Map to native classes
    native "ios", "MyComponentView"
    native "android", "com.myapp.MyComponent"

    # Declare capabilities
    capability :gestures
    capability :accessibility
  end
end
```

### Property Types

| Type | Description |
|------|-------------|
| `:string` | UTF-8 string |
| `:bool` | Boolean (true/false) |
| `:integer` | Signed 64-bit integer |
| `:float` | 64-bit float |
| `:f32` | 32-bit float (binary protocol) |
| `:f64` | 64-bit float (binary protocol) |
| `:color` | Color token or ARGB integer |
| `:binary` | Binary data |
| `:list` | List of values |
| `:map` | Map/dictionary |

### Property Options

- `:required` - If true, prop must be provided (default: `false`)
- `:default` - Default value if not provided
- `:doc` - Documentation string

### Events

```elixir
event "progress"
event "completed", payload: %{percentage: :f32, time: :integer}
```

### Capabilities

| Capability | Description |
|------------|-------------|
| `:gestures` | Handles pan/zoom/rotate gestures |
| `:accessibility` | Provides accessibility tree |
| `:animation` | Supports custom animations |
| `:textures` | Renders to texture (e.g., camera, AR) |
| `:overlay` | Can render above other content |
| `:clipping` | Supports clipping masks |
| `:touch` | Handles raw touch events |
| `:keyboard` | Handles keyboard input |
| `:focus` | Participates in focus navigation |

## Using Plugins

### Registration

Register your plugin at application startup:

```elixir
defmodule MyApp do
  use Dala.App

  def on_start do
    # Register plugins
    MyApp.VideoPlugin.register()
    MyApp.MapPlugin.register()
    MyApp.ChartPlugin.register()

    # Start your root screen
    Dala.Screen.Screen.start_root(MyApp.HomeScreen)
  end
end
```

### In Screens

Use plugin components just like built-in components:

```elixir
defmodule MyApp.VideoScreen do
  use Dala.Screen

  def render(assigns) do
    %{
      type: "video",
      props: %{
        source: @video_url,
        autoplay: true,
        controls: true,
        volume: 0.8
      },
      children: []
    }
  end

  def handle_event("progress", %{"position" => pos, "duration" => dur}, socket) do
    {:noreply, Dala.Socket.assign(socket, :progress, pos / dur)}
  end

  def handle_event("ended", _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :finished, true)}
  end
end
```

### With Lists

```elixir
def render(assigns) do
  %{
    type: :list,
    props: %{
      id: :videos,
      items: @videos
    },
    children: [
      %{
        type: "video",
        props: %{
          source: "{{item.url}}",
          autoplay: false,
          width: 300,
          height: 200
        }
      }
    ]
  }
end
```

## Protocol Generation

Dala automatically generates binary protocol specifications from plugin schemas:

```elixir
# Generate protocol
protocol = MyApp.VideoPlugin.generate_protocol()

# Generate manifest
manifest = MyApp.VideoPlugin.generate_manifest()

# Write to file
MyApp.VideoPlugin.generate_manifest()
|> MyApp.VideoPlugin.write_to_file("priv/manifest.json")
```

### Field Numbering

Each property gets a unique field number:

```elixir
prop "volume", :f32
# → FIELD_VOLUME = 0x02
# → [f32]
```

Field numbers are assigned sequentially starting from `0x01` for each component, ensuring no collisions within a plugin.

### Binary Format

```
+--------+--------+--------+--------+
| opcode |  id    | field  | value  |
+--------+--------+--------+--------+
  1 byte  8 bytes  1 byte  N bytes
```

## Native Implementation

### iOS (Swift)

```swift
dalaNativeViewRegistry.shared.register("video") { props, send in
    let player = AVPlayer(url: URL(string: props["source"])!)
    player.automaticallyWaitsToMinimizeStalling = false

    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = props["controls"] as? Bool ?? true

    if props["autoplay"] as? Bool ?? false {
        player.play()
    }

    // Send progress events
    let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
    player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
        let position = CMTimeGetSeconds(time)
        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? CMTime.zero)
        send("progress", [
            "position": position,
            "duration": duration
        ])
    }

    return controller
}
```

### Android (Kotlin)

```kotlin
dalaNativeViewRegistry.register("video") { props, send ->
    val view = PlayerView(context).apply {
        val player = ExoPlayer.Builder(context).build()
        this.player = player

        player.setMediaItem(MediaItem.fromUri(props["source"]))
        player.playWhenReady = props["autoplay"] as? Boolean ?: false
        useController = props["controls"] as? Boolean ?: true

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) {
                    send("ended", mapOf())
                }
            }
        })

        // Send progress events
        val handler = Handler(Looper.getMainLooper())
        handler.post(object : Runnable {
            override fun run() {
                val position = player.currentPosition
                val duration = player.duration
                send("progress", mapOf(
                    "position" to position,
                    "duration" to duration
                ))
                handler.postDelayed(this, 500)
            }
        })
    }
    view
}
```

## Plugin Registry

The plugin registry manages all registered plugins:

```elixir
# Look up a component's plugin
{:ok, plugin} = Dala.Plugin.Registry.lookup_component("video")

# List all components
Dala.Plugin.Registry.list_components()
# → ["video", "map", "chart", ...]

# Check capabilities
Dala.Plugin.Registry.supports_capability?(:gestures)
# → true

# Get components with a capability
Dala.Plugin.Registry.components_with_capability(:gestures)
# → ["video", "map", "chart"]

# List all capabilities
Dala.Plugin.Registry.list_capabilities()
# → [:gestures, :accessibility, :animation, ...]
```

## Dynamic Plugin Loading

Plugins can be loaded dynamically at runtime:

```elixir
# Load manifest from JSON
{:ok, manifest} = File.read!("priv/plugins/video.json")
|> JSON.decode!()
|> Dala.Plugin.Manifest.from_json()

# Register all components
Dala.Plugin.Manifest.register_from_manifest(manifest)
```

## Best Practices

1. **Version Everything**: Always declare `schema_version`, `protocol_version`, and `native_api_version`

2. **Schema-First**: Design the schema before implementing native views

3. **Capabilities**: Declare capabilities accurately so the runtime can optimize

4. **Events**: Use descriptive event names and document payloads

5. **Defaults**: Provide sensible defaults for all optional props

6. **Validation**: Use `required: true` for essential props

7. **Documentation**: Document props, events, and capabilities

8. **Testing**: Test with the Dala test harness:

```elixir
test "video autoplay" do
  {:ok, pid} = Dala.Screen.start_link(MyApp.VideoScreen)
  Dala.Test.tap(pid, :play_button)
  assert Dala.Test.assigns(pid).autoplay == true
end
```

## Migration Guide

### From Native Views

If you have existing native view components:

1. Create a plugin module with `use Dala.Plugin`
2. Define your component schema with `component/2`
3. Add props, events, and capabilities
4. Map to your existing native class with `native/2`
5. Register the plugin

No changes to native code required!

### From Widgets

If you have custom Elixir widgets:

1. Extract the UI logic into a plugin schema
2. Define props and events
3. Implement as a native view or keep as Elixir process
4. Use `Dala.Ui.Widgets.native_view/2` for hybrid approach

## Future Features

- **Remote Components**: Stream components from server
- **Hot Install**: Install plugins without app update
- **Visual Builders**: Drag-and-drop UI construction
- **AI Generation**: Generate UIs from descriptions
- **Cross-Platform Sharing**: Share plugins across iOS/Android

## Examples

See the following example plugins:

- `Dala.Plugin.VideoPlugin` - Video player component
- `Dala.Plugin.MapPlugin` - Interactive map
- `Dala.Plugin.ChartPlugin` - Data visualization

## Troubleshooting

**Component not rendering?**

- Check that the plugin is registered: `Dala.Plugin.Registry.list_components()`
- Verify the component type matches the schema
- Ensure the `:id` prop is provided

**Events not firing?**

- Check event names match between schema and native code
- Verify the native implementation calls `send/2`
- Ensure `handle_event/3` is implemented in the screen

**Props not updating?**

- Verify prop types match the schema
- Check that required props are provided
- Ensure the component process is running

## Summary

The plugin architecture enables:

- **Extensibility**: Add new components without modifying core
- **Portability**: Same schema works across platforms
- **Tooling**: Auto-generated code and documentation
- **Ecosystem**: Third-party plugin marketplace potential
- **Scalability**: Core stays tiny, plugins handle complexity

This is the foundation for a thriving plugin ecosystem where developers can build, share, and reuse components across projects and platforms.
