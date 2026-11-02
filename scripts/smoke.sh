#!/bin/sh
# Smoke test: start the server over stdio and call the read-only tools against the live registry.
# usage: scripts/smoke.sh build/c3pkg-mcp
set -eu
bin=${1:-build/c3pkg-mcp}
out=$(printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
 '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_packages","arguments":{"per_page":1}}}' \
 '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_package","arguments":{"name":"does-not-exist"}}}' \
 | "$bin" 2>/dev/null)
echo "$out" | grep -q '"name":"download_package"' || { echo "tools/list failed"; exit 1; }
echo "$out" | grep -q 'packages' || { echo "search failed"; exit 1; }
echo "$out" | grep -q 'HTTP 404' || { echo "error mapping failed"; exit 1; }
echo "smoke ok"
