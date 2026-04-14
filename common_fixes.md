# Common Fixes & Pitfalls

## `+C` flags crash BEAM silently on Android (exit(1), no logcat output)

**Symptom**: App exits cleanly with code 1 within ~60ms of `erl_start`. No Erlang code
runs (no diagnostic files written). BEAM stderr goes to `/dev/null` on Android, so no
error message is visible in logcat. The last logcat line is the symlink logs from
`mob_start_beam`.

**Root cause**: `erl_start` is called directly (bypassing `erlexec`). The BEAM arg
parser in `erl_start` requires all emulator flags to start with `-`. Any `+`-prefixed
arg (e.g. `+C multi_time_warp`) hits:

```c
if (argv[i][0] != '-') erts_usage();   // → exit(1) with no output
```

`erlexec` normally translates `+` flags to `-` before passing them to the BEAM, but
mob_beam.c calls `erl_start` directly.

**Fix**: Use `-C multi_time_warp` instead of `+C multi_time_warp`. Or omit it entirely
— `multi_time_warp` is already the default in OTP 28 (erts-16.3).

**Fixed in**: `mob/android/jni/mob_beam.c` — removed `"+C", "multi_time_warp"` from
`BEAM_EXTRA_FLAGS` (2026-04-14).

---

## Android BEAM stderr is silent

All ERTS error output (arg parse errors, boot failures, `erts_usage()`) goes to fd 2
(stderr). On Android, stderr from JNI threads goes to `/dev/null`, not logcat.

To capture BEAM stderr for diagnosis, redirect fd 2 to a file before calling
`erl_start`:

```c
char stderr_log[580];
snprintf(stderr_log, sizeof(stderr_log), "%s/beam_stderr.log", s_files_dir);
int fd = open(stderr_log, O_CREAT | O_WRONLY | O_TRUNC, 0644);
if (fd >= 0) { dup2(fd, STDERR_FILENO); close(fd); }
```

Then after crash: `adb shell "run-as com.mob.demo cat /data/user/0/com.mob.demo/files/beam_stderr.log"`

---

## iOS BEAM crashes with `eaddrinuse` when Android is also connected

**Symptom**: iOS simulator app exits immediately. `xcrun simctl launch --console` shows:
`Protocol 'inet_tcp': register/listen error: eaddrinuse`

**Root cause**: `mob_beam.m` defaults to dist port 9100 when `MOB_DIST_PORT` is not set.
When an Android device is connected, `adb forward tcp:9100 tcp:9100` is active and holds
port 9100 on localhost. The iOS BEAM tries to bind the same port for Erlang distribution
and fails.

**Fix**: Default iOS dist port changed from 9100 → 9101 in `mob/ios/mob_beam.m`.
Per the port assignment scheme: Android = 9100, iOS sim = 9101.
Requires a native rebuild (`mix mob.deploy --native --ios`).

**Fixed in**: `mob/ios/mob_beam.m` (2026-04-14).

---

## Dashboard LiveView crash: `process_keyed/5 ArgumentError`

**Symptom**: `mob_dev` Phoenix LiveView server crashes with `ArgumentError` in
`Phoenix.LiveView.Diff.process_keyed/5` during rapid log ingestion.

**Root causes (three separate issues)**:
1. `phx-update="stream"` and `phx-hook="ScrollBottom"` on the **same** element — explicitly
   prohibited by LiveView. Hook must be on an outer wrapper; stream on an inner element.
2. Variable name collision: loop variable `line` used in both deploy output `:for` and
   the stream `:for` iterator.
3. Double `:if` directives inside stream items — use `<%= if %>...<% else %>...<% end %>`
   instead.

**Fixed in**: `mob_dev/lib/mob_dev/server/live/dashboard_live.ex` — converted log list
to a Phoenix stream, separated hook/stream elements, renamed loop variable.

---

## `mix mob.deploy` silently skips updating BEAM files

**Symptom**: `mix mob.deploy --ios` reports "Pushing N BEAM file(s) ✓" but the deployed
beams in `/tmp/otp-ios-sim/<app>/` retain old timestamps and old content (e.g. `mob_nif.beam`
missing `log/2` export even after force-recompiling the dep).

**Root cause**: `Deployer.deploy_ios/3` runs `System.cmd("cp", ["-r", "#{dir}/.", dest])`
where `dir` is a relative path like `_build/dev/lib/mob_demo/ebin`. `System.cmd` spawns an
OS subprocess that uses the **OS process CWD**, not the Erlang process CWD. Mix sets the
Erlang CWD to the project root via `:file.set_cwd`, but this doesn't affect the OS CWD of
spawned subprocesses. If the two differ (e.g. because Mix compiled a dep in a sub-directory),
the relative path resolves to the wrong location and `cp` silently exits 0 with no matching
source files.

**Fix**: Use `Path.expand(dir)` before passing to `System.cmd`, which resolves the relative
path against `File.cwd!()` (the Erlang process CWD, correctly set to the project root).

**Fixed in**: `mob_dev/lib/mob_dev/deployer.ex` — both `deploy_ios/3` and
`push_beams_android/2` now use `Path.expand(dir)` (2026-04-14).
