# Event System Audit (Batch 2)

Snapshot of the event-emission surface as of Batch 1 completion. Pairs with
`event_model.md` (the design) — this is "what's there now and how it maps."

## Event props recognised by the renderer

`lib/dala/renderer.ex` translates these node prop keys into native handle
registrations. Each is opt-in per widget; absence means no event delivery.

### Tap-family (existing)

| Prop | Form accepted | Native message | Notes |
|------|---------------|----------------|-------|
| `on_tap` | `pid \| {pid, tag}` | `{:tap, tag}` | `tag` defaults to `:ok` for bare pid; when atom, also emits `accessibility_id` for test tooling |
| `on_change` | `{pid, tag}` | `{:change, tag, value}` | text_field (binary), toggle (boolean atom), slider (float) |
| `on_focus` | `{pid, tag}` | `{:focus, tag}` | text_field |
| `on_blur` | `{pid, tag}` | `{:blur, tag}` | text_field |
| `on_submit` | `{pid, tag}` | `{:submit, tag}` | text_field return key |
| `on_end_reached` | `{pid, tag}` | `{:end_reached, tag}` | scroll position pagination trigger |
| `on_tab_select` | `{pid, tag}` | `{:tab_select, tag, tab_id}` | tab bars |

### New (Batch 3 / Batch 4 added in this pass)

| Prop | Form accepted | Native message | Status |
|------|---------------|----------------|--------|
| `on_select` | `{pid, tag}` | `{:select, tag}` | Renderer + iOS NIF wired; Android wired |
| `on_long_press` | `{pid, tag}` | `{:long_press, tag}` | Renderer + iOS NIF + native gesture; Android wired |
| `on_double_tap` | `{pid, tag}` | `{:double_tap, tag}` | Same |
| `on_swipe` | `{pid, tag}` | `{:swipe, tag, direction}` | Direction is `:left \| :right \| :up \| :down` |
| `on_swipe_left` | `{pid, tag}` | `{:swipe_left, tag}` | Specific direction only |
| `on_swipe_right` | `{pid, tag}` | `{:swipe_right, tag}` | |
| `on_swipe_up` | `{pid, tag}` | `{:swipe_up, tag}` | |
| `on_swipe_down` | `{pid, tag}` | `{:swipe_down, tag}` | |

## Existing native event paths

### iOS (`dala_nif.m` → `DalaRootView.swift`)

- Tap-family: SwiftUI `.onTapGesture { closure() }` calls `dala_send_*` from
  the closure stored on `DalaNode`. Closure was wired by the JSON deserialiser
  using the integer handle from `register_tap`.
- Audio session and lifecycle observers: `[NSNotificationCenter defaultCenter]`
  with blocks that `enif_send` to a registered dispatcher pid.
- Gestures (new in this pass): `extension View { func dalaGestures(_:) }` adds
  `.onLongPressGesture`, `.onTapGesture(count: 2)`, and a `DragGesture`
  (only when at least one swipe handler is set, to avoid interfering with
  ScrollView).

### Android (`android/jni/dala_nif.c` + `dalaBridge.kt`)

- Tap-family: same handle-lookup pattern via `dala_send_*` C functions called
  from JNI stubs (`Java_..._dalaBridge_nativeSendTap`).
- Gestures (new in this pass): C senders declared and exported via
  `dala_beam.h`. JNI stubs in `beam_jni.c` and Compose `Modifier` setup in the
  generated app's `dalaBridge` are still pending — see "Pending native work."

## Bridge to canonical envelope

Today, screens receive legacy shapes (`{:tap, tag}`, `{:change, tag, value}`).
`Dala.Event.Bridge` converts these to the canonical
`{:dala_event, %Address{}, event, payload}` envelope on demand. Screens can
opt in incrementally:

```elixir
def handle_info(msg, socket) do
  case Dala.Event.Bridge.legacy_to_canonical(msg, __MODULE__) do
    {:ok, envelope} -> handle_canonical(envelope, socket)
    :passthrough    -> # not a recognised legacy shape — handle directly
  end
end
```

When all native emitters are migrated to the canonical envelope, this bridge
can be removed.

## Pending native work

### iOS

- ✅ NIF entry points (`dala_send_long_press`, `dala_send_double_tap`,
  `dala_send_swipe_*`)
- ✅ DalaNode property declarations (`onLongPress`, `onDoubleTap`,
  `onSwipe`, `onSwipeLeft`, `onSwipeRight`, `onSwipeUp`, `onSwipeDown`)
- ✅ Prop deserialiser wires them up
- ✅ SwiftUI `.dalaGestures()` modifier applies them
- ⏳ Verify on physical device — gesture conflicts with scroll need real-world
  testing

### Android

- ✅ C sender functions (`dala_send_long_press` etc.)
- ✅ Header export in `dala_beam.h`
- ⏳ JNI stubs in `beam_jni.c` (need entries calling the C functions)
- ⏳ Kotlin `dalaBridge` JNI declarations
- ⏳ Compose `Modifier` setup — `pointerInput { detectTapGestures(...) }` for
  long-press/double-tap, `detectDragGestures` for swipes, gated per-node by
  the corresponding handle being non-null

## Migration path for `Dala.List`

Currently `Dala.List` is a render helper, not a stateful component. Each row
gets `on_tap: {screen_pid, {:list, list_id, :select, index}}`. `Dala.Screen`
has hardcoded knowledge of this shape and re-emits as `{:select, list_id, index}`.

Under the new event model, this becomes a stateful component (planned, not in
this pass):

1. `Dala.List` becomes a `Dala.Event.StatefulComponent` (see future module)
2. Row taps target the list's pid, not the screen's
3. List handles row events internally (selection state, scroll position,
   etc.) and emits semantic events upward to its parent

Until that lands, the bridge module handles the existing list-tap shape:
`{:tap, {:list, id, :select, index}}` →
`{:dala_event, addr(:list, id, instance: index), :select, nil}`.

## Tests

| Module | Coverage |
|--------|----------|
| `Dala.Event.Address` | 47 tests + 10 doctests (struct, validation, formatting, pattern matching) |
| `Dala.Event.Target` | 17 tests + 3 doctests (every target form + classification) |
| `Dala.Event` | 20 tests + 4 doctests (dispatch, emit, matchers, test helpers) |
| `Dala.Event.Bridge` | 19 tests + 4 doctests (each legacy shape + passthrough) |
| `Dala.Renderer` | 9 new tests (Batch 3 + Batch 4 prop registration) |

Total Dala.Event-related tests added in this pass: **125 + doctests**.
