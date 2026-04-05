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

  def handle_event("tap", _params, socket) do
    {:noreply, Mob.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end
end
```

- **Android:** native Views via JNI, no WebView
- **iOS:** UIKit via Objective-C NIFs, no WebView
- **State management:** `Mob.Screen` GenServer with `mount/3`, `render/1`, `handle_event/3`, `handle_info/2`
- **Boot time:** ~64ms to first Elixir line on iOS simulator (M4 Pro)

## Installation

```elixir
def deps do
  [
    {:mob, "~> 0.1.0"}
  ]
end
```

## Source

[github.com/kevinbsmith/mob](https://github.com/kevinbsmith/mob)
