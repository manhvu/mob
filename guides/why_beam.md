# Why the BEAM?

## Your app is a distributed system whether you like it or not

A mobile app talks to a server, handles push notifications while in the
background, manages local state, streams data, processes user input — all
concurrently, all the time. Most frameworks pretend this isn't true and make you
assemble it from callbacks, promises, state machines, and background workers.
You spend more time wiring concurrency plumbing than building your app.

The BEAM was designed in 1986 for telephone exchanges — systems that handle
millions of concurrent connections, never go down, and update themselves while
running. It didn't get these properties by accident. They are the entire point.
When you run the BEAM on a phone, you get all of it.

## What that actually means

**Concurrency that doesn't hurt.** Every screen is a `GenServer`. Every
background task is a supervised process. You don't choose between async/await
patterns and state machines — you just write functions that send messages.
Ten thousand concurrent processes on a phone costs less than one thread in most
runtimes.

**Fault isolation by default.** A crash in one screen cannot corrupt another.
The supervisor restarts it. You don't write defensive code everywhere — you let
things crash and write recovery logic once, at the top of the tree.

**Hot code loading.** Push new BEAM files to a running app and the code changes
in place — no restart, no lost state, no user impact. This works in development
(see `mix mob.deploy`) and it works in production via OTA update. No App Store
review required for Elixir changes.

**Distribution is a first-class primitive.** This is the one that changes what
apps are possible.

## Mob.Cluster: phones as nodes

In the BEAM, every running instance is a *node*. Nodes connect to each other
over Erlang distribution and immediately share the full OTP primitive set:
remote procedure calls, message passing to a pid on another machine, distributed
process registries, global GenServers.

Two Mob apps that share a cookie become a cluster:

```elixir
Mob.Cluster.join(:"their_app@192.168.1.42", cookie: :session_token)

# Now this works, across devices, over WiFi, with no server:
:rpc.call(:"their_app@192.168.1.42", TheirApp.GameServer, :move, [:left])
GenServer.call({MyServer, :"their_app@192.168.1.42"}, :get_state)
```

This is not a protocol you built. It is not a WebSocket layer. It is Erlang
distribution — the same thing that has been running telecoms switches, trading
systems, and WhatsApp's backend (two million connections per server, in 2012,
on hardware that would embarrass a modern phone) for decades.

The implications for mobile:

- **Multiplayer without a server.** Two phones, local network, no backend. Real
  state synchronisation, not eventual consistency hacks.
- **Handoff.** Start something on one device, continue on another. The state
  is already there — it's just a pid on a different node.
- **Collaborative apps.** Shared documents, live cursors, multi-user canvases —
  built with the same primitives you use for everything else, not a specialised
  CRDT library bolted on.
- **Device as a node in your backend cluster.** The phone is not a client
  polling an API. It is a peer in your OTP supervision tree. Your server can
  call functions on the device as easily as the device calls functions on the
  server.

## The update story

Most apps treat an update as a full binary replacement — compile, submit, review,
release, hope users install it. Because the BEAM separates code from state, you
can push new modules to a running app and they take effect immediately. The
running processes pick up the new code on their next function call. No restart.
No lost session. No App Store wait for Elixir changes.

Combined with on-demand distribution (start a cluster connection, receive new
BEAMs, disconnect), OTA updates become a first-class feature rather than a
platform workaround.

## Battery consumption

The BEAM has a reputation for being hard on mobile batteries. The numbers below
are measured on a physical iPhone with the screen on (required — see note), which
means each run includes screen consumption. All runs use the same conditions so the
results are directly comparable.

| Mode | Start | End (30 min) | Drain | Rate |
|------|-------|--------------|-------|------|
| Default (Nerves tuning) | 100% | 97% | 3% | ~6%/hr |
| No BEAM (native baseline) | 100% | 100% | 0% | ~0%/hr |
| Untuned BEAM | — | — | — | — |

_Untuned run pending. Table will be updated._

**How to read this:** the no-beam baseline shows that running a native iOS app at
minimum screen brightness costs essentially nothing over 30 minutes. The BEAM with
Nerves tuning adds ~6%/hr — similar to leaving the screen on at moderate brightness.
The untuned row will show how much worse it gets without scheduler tuning, which is
what gives the BEAM its battery reputation.

**Methodology:** `mix mob.battery_bench_ios` builds and installs the app, connects to
the device BEAM over WiFi, reads battery every 10 seconds via `mob_nif:battery_level/0`,
and reports drain and rate. The 30-minute duration is the default; longer runs give
better rate estimates. The Nerves-tuned run was measured with the screen on (required
at the time — the app was not yet background-capable). The no-beam run was measured
at minimum screen brightness; battery read via `ideviceinfo` at start and end (USB
connected briefly for reads only). The screen-off BEAM run uses `Mob.Background`
keep-alive and is currently in progress.

**Resolution note:** `UIDevice.batteryLevel` reports in 5% increments on real
hardware (an iOS privacy measure). The actual drain may be finer; when USB is
connected `ideviceinfo BatteryCurrentCapacity` gives 1% resolution. In the first
run above, the 5% gauge snapped to 95% at exactly 30 minutes but USB confirmed 97%.

## The honest trade-off

The BEAM is not free. You are writing Elixir, not JavaScript or Swift. The
ecosystem is smaller. Some things that are trivial in React Native — a particular 
animation library, a specific native SDK wrapper — require more work. But the things that 
are impossible on React Native are possible now.

What you are buying is a runtime that was engineered for exactly the problem
mobile apps have: high concurrency, fault tolerance, live updates, distributed
state. You are not adapting a web runtime or a game engine to the mobile
problem. You are using a tool that was built for it, forty years before the
iPhone existed.

If your app is a thin wrapper around an API with a few screens, the trade-off
probably isn't worth it. If your app has meaningful real-time behaviour, local
state that matters, multi-user interaction, or a need to update without
resubmitting to an app store — the BEAM earns its place.
