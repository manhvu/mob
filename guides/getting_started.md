# Getting Started

This guide walks you through creating a new Mob app from scratch, running it on a simulator, and making your first code change with hot push.

## Prerequisites

- Elixir 1.18 or later
- `mob_dev` installed globally: `mix archive.install hex mob_dev`
- For iOS: Xcode 15+ and the iOS simulator
- For Android: Android Studio with an AVD (Android Virtual Device)

## Create a new app

```bash
mix mob.new my_app
cd my_app
```

`mix mob.new` generates a complete project: Elixir sources, a native iOS project, and a native Android project. The Elixir code lives in `lib/`; native projects live in `ios/` and `android/`.

## Project structure

```
my_app/
├── lib/
│   ├── my_app.ex          # Mob.App entry point
│   └── my_app/
│       └── home_screen.ex # Your first screen
├── ios/
│   └── MyApp.xcodeproj    # Open in Xcode to build and run
├── android/
│   └── app/               # Open in Android Studio
└── mix.exs
```

## Run on iOS simulator

```bash
# Build and launch in the booted iOS simulator
mix mob.deploy --ios
```

Or open `ios/MyApp.xcodeproj` in Xcode, select a simulator, and press Run.

## Run on Android emulator

```bash
# Build and launch in the running Android emulator
mix mob.deploy --android
```

Or open the `android/` folder in Android Studio and press Run.

## Connect a live IEx session

Once the app is running:

```bash
mix mob.connect
```

This tunnels EPMD, sets up Erlang distribution, and drops you into an IEx session connected to the running BEAM node on the device. You can inspect state, call functions, and push code changes without restarting the app.

```elixir
# Verify the device node is visible
Node.list()
#=> [:"my_app_ios@127.0.0.1"]

# Inspect the current screen's assigns
Mob.Test.assigns(:"my_app_ios@127.0.0.1")
#=> %{safe_area: %{top: 62.0, ...}}
```

## Hot-push a code change

Edit a screen module, recompile, and push the new bytecode to the running app:

```bash
# In the terminal (not inside IEx):
mix compile && nl(MyApp.HomeScreen)
```

The screen updates instantly. No restart, no rebuild.

## Your first screen

A minimal screen:

```elixir
defmodule MyApp.HomeScreen do
  use Mob.Screen

  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :count, 0)}
  end

  def render(assigns) do
    %{
      type: :column,
      props: %{padding: 24, gap: 16},
      children: [
        %{type: :text, props: %{text: "Count: #{assigns.count}", text_size: :xl}, children: []},
        %{type: :button, props: %{text: "Tap me", on_tap: {self(), :increment}}, children: []}
      ]
    }
  end

  def handle_event("tap", %{"tag" => "increment"}, socket) do
    {:noreply, Mob.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end
end
```

`mount/3` initialises assigns. `render/1` returns the component tree as a plain Elixir map. `handle_event/3` updates assigns in response to user interaction. After each callback that returns a modified socket, the framework calls `render/1` again and pushes the diff to the native layer.

## App entry point

Your app module declares navigation and starts the root screen:

```elixir
defmodule MyApp do
  use Mob.App

  def navigation(_platform) do
    stack(:home, root: MyApp.HomeScreen)
  end

  def on_start do
    Mob.Screen.start_root(MyApp.HomeScreen)
  end
end
```

`use Mob.App` generates a `start/0` entry point that the BEAM launcher calls. It handles framework initialization (logger, navigation registry) before calling your `on_start/0`.

## Next steps

- [Screen Lifecycle](screen_lifecycle.md) — understand mount, render, handle_event, handle_info
- [Components](components.md) — the full component reference
- [Navigation](navigation.md) — stack, tab bar, drawer, push/pop
- [Theming](theming.md) — color tokens, named themes, runtime switching
- [Device Capabilities](device_capabilities.md) — camera, location, haptics, notifications
- [Testing](testing.md) — unit tests and live device inspection
