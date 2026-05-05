#!/bin/bash
# Test script for WebView interact API

echo "Testing WebView Interact API..."
echo ""

echo "1. Checking if required files exist:"
echo "  - dala/lib/dala/webview.ex: $([ -f lib/dala/webview.ex ] && echo 'YES' || echo 'NO')"
echo "  - dala/lib/dala/test.ex: $([ -f lib/dala/test.ex ] && echo 'YES' || echo 'NO')"
echo "  - dala/native/dala_nif/src/lib.rs: $([ -f native/dala_nif/src/lib.rs ] && echo 'YES' || echo 'NO')"
echo "  - dala/ios/dalaRootView.swift: $([ -f ios/dalaRootView.swift ] && echo 'YES' || echo 'NO')"
echo "  - dala/examples/webview_interact.examples.md: $([ -f examples/webview_interact.examples.md ] && echo 'YES' || echo 'NO')"
echo "  - dala/guides/rustler_in_dala.md: $([ -f guides/rustler_in_dala.md ] && echo 'YES' || echo 'NO')"
echo ""

echo "2. Checking Rust code compilation:"
cd native/dala_nif && cargo check 2>&1 | grep -E "error|warning|Finished" | head -10
echo ""

echo "3. Checking Elixir code formatting:"
cd ../..
mix format --check-formatted lib/dala/webview.ex lib/dala/test.ex 2>&1 | head -5
echo ""

echo "4. Checking Elixir code with Credo:"
mix credo --strict lib/dala/webview.ex lib/dala/test.ex 2>&1 | head -10
echo ""

echo "Test complete!"
