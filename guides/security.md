# Security Guide

Security considerations for Mob applications — from development to production.

## Erlang Distribution Security

Mob apps run real Erlang nodes that can accept remote connections via
`Node.connect/1`. This is powerful for development but dangerous if
misconfigured in production.

### The Risk

If an attacker learns your distribution cookie, they can:

- Connect to your app's Erlang node from anywhere on the network
- Call any exported function, including `Mob.Diag` helpers
- Load and execute arbitrary code via `:code.load_binary/3`
- Access sensitive data in application state

### Secure Cookie Practices

**Never hardcode cookies:**

```elixir
# ❌ NEVER DO THIS
Mob.Dist.ensure_started(node: :"my_app@127.0.0.1", cookie: :secret)
Mob.Dist.ensure_started(node: :"my_app@127.0.0.1", cookie: :mob_secret)
```

**Generate strong cookies per app:**

```elixir
# ✅ Generate a strong random cookie
# In your shell:
#   openssl rand -hex 32
#   9f3a7b2c8d1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f

# In your app's on_start/0:
def on_start do
  cookie = Mob.Dist.cookie_from_env("MY_APP_DIST_COOKIE", "my_app")
  Mob.Dist.ensure_started(node: :"my_app@127.0.0.1", cookie: cookie)
end

# Set the env var at deploy time:
MY_APP_DIST_COOKIE=9f3a... mix mob.deploy --device <udid>
```

**Rotate cookies periodically:**

```elixir
# In a running system, you can rotate without restarting:
Node.set_cookie(new_secure_cookie)
```

### Network Exposure

**Development (safe defaults):**
- iOS simulator shares Mac's network — only accessible locally
- Android via `adb reverse` tunnels — only accessible via USB

**Production (lock it down):**
- Use firewalls/VPC to restrict ports 9100 and 4369
- Only allow trusted IPs to connect
- Consider running without distribution in production apps that don't need it
- Set `MOB_RELEASE=1` to disable distribution at the C layer

### The `Mob.Diag` Module

`Mob.Diag` is shipped in every Mob app and provides introspection capabilities.
If distribution credentials leak, it becomes a target for information disclosure.

**Mitigation:**
1. Use strong, unique cookies (see above)
2. Strip `Mob.Diag` in release builds (code trimming / dead code elimination)
3. Monitor and alert on unexpected node connections
4. Consider disabling distribution entirely for apps that don't need remote access

## Push Notifications

Push notification tokens (`Mob.Notify.register_push/1`) must be transmitted
securely to your server.

**Best practices:**
- Use HTTPS/TLS for token transmission
- Validate tokens on the server side
- Don't log raw tokens in plaintext
- Rotate tokens periodically (re-register push)
- Use the `mob_push` library which handles secure transmission

## Biometric Authentication

`Mob.Biometric.authenticate/2` delegates to platform APIs (Face ID, Touch ID,
fingerprint). The result arrives asynchronously via `handle_info`.

**Considerations:**
- No rate limiting is built in — implement your own if needed
- Results come via message passing — validate the source
- Biometric hardware may not be available — handle `:not_available`
- No replay protection — each auth is independent

## File System Security

Mob apps use temporary paths for file pickers:

```elixir
# mob/lib/mob/files.ex
%{path: "/tmp/mob_file_xxx.pdf", ...}
```

**Recommendations:**
- `/tmp/` may be world-readable on some systems
- Delete sensitive files after use
- Don't store credentials or secrets in temporary files
- Use platform secure storage APIs for sensitive data

## Environment Variables

Mob reads several environment variables at runtime:

| Variable | Purpose | Security Note |
|----------|---------|---------------|
| `MOB_RELEASE` | Disables distribution in release builds | Set to `1` for App Store builds |
| `MOB_NODE_SUFFIX` | Makes node names unique per device | Set by launcher, not user-controllable |
| `MOB_DATA_DIR` | Overrides default data directory | Ensure path is secure |
| `HOME` | Fallback for cookie file location | Sandboxed on iOS/Android |
| `LIBMLX_ENABLE_JIT` | Enables MLX JIT (iOS) | Set to `false` on iOS devices (W^X policy) |

**Never put secrets in environment variables that are:**
- Logged by the system
- Visible in `ps` output
- Committed to source control

## Dependency Security

Mob depends on several Hex packages. Audit them regularly:

```bash
# Check for known vulnerabilities
mix hex.audit

# Update dependencies
mix deps.update --all

# Check for outdated packages
mix hex.outdated
```

Add `mix hex.audit` to your CI pipeline.

## Secure Development Workflow

1. **Generate a strong cookie** for your app:
   ```bash
   openssl rand -hex 32
   ```

2. **Store it securely** — use your CI/CD secret storage, not `.env` files

3. **Set it at deploy time**:
   ```bash
   MY_APP_DIST_COOKIE=<your-cookie> mix mob.deploy --device <udid>
   ```

4. **Verify no hardcoded cookies** in your codebase:
   ```bash
   grep -r "cookie: :" lib/
   ```

5. **Test with release mode** to ensure distribution is disabled:
   ```bash
   MOB_RELEASE=1 mix mob.deploy --device <udid>
   ```

## Reporting Security Issues

If you discover a security vulnerability in Mob itself:

- **Do not** open a public GitHub issue
- Email the maintainers directly
- Include steps to reproduce and potential impact
- Allow time for a patch before public disclosure

## Checklist

Before shipping your Mob app:

- [ ] No hardcoded distribution cookies in source code
- [ ] Strong random cookie set via environment variable
- [ ] `MOB_RELEASE=1` set for App Store/Play Store builds
- [ ] Push notification tokens transmitted over HTTPS only
- [ ] Sensitive files cleaned up after use
- [ ] Dependencies audited with `mix hex.audit`
- [ ] Distribution ports (9100, 4369) firewalled in production
- [ ] Monitoring/alerting on unexpected node connections (if distribution enabled)
- [ ] `Mob.Diag` considered for removal in production builds
