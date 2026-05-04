#!/bin/bash
# Test script for WebView interact API

echo "Testing WebView Interact API..."
echo ""

echo "1. Checking if required files exist:"
echo "  - mob/lib/mob/webview.ex: $([ -f lib/mob/webview.ex ] && echo 'YES' || echo 'NO')"
echo "  - mob/lib/mob/test.ex: $([ -f lib/mob/test.ex ] && echo 'YES' || echo 'NO')"
echo "  - mob/native/mob_nif/src/lib.rs: $([ -f native/mob_nif/src/lib.rs ] && echo 'YES' || echo 'NO')"
echo "  - mob/ios/MobRootView.swift: $([ -f ios/MobRootView.swift ] && echo 'YES' || echo 'NO')"
echo "  - mob/examples/webview_interact.examples.md: $([ -f examples/webview_interact.examples.md ] && echo 'YES' || echo 'NO')"
echo "  - mob/guides/rustler_in_mob.md: $([ -f guides/rustler_in_mob.md ] && echo 'YES' || echo 'NO')"
echo ""

echo "2. Checking Rust code compilation:"
cd native/mob_nif && cargo check 2>&1 | grep -E "error|warning|Finished" | head -10
echo ""

echo "3. Checking Elixir code formatting:"
cd ../..
mix format --check-formatted lib/mob/webview.ex lib/mob/test.ex 2>&1 | head -5
echo ""

echo "4. Checking Elixir code with Credo:"
mix credo --strict lib/mob/webview.ex lib/mob/test.ex 2>&1 | head -10
echo ""

echo "Test complete!"
