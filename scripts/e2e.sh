#!/bin/sh
# End-to-end test of every tool against scripts/mock_server.py (no network or real token needed).
# usage: scripts/e2e.sh [build/c3pkg-mcp]
set -eu
bin=$(realpath "${1:-build/c3pkg-mcp}")
mock=$(realpath "$(dirname "$0")/mock_server.py")
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
tmp=$(mktemp -d); trap 'kill $srv 2>/dev/null; rm -rf "$tmp"' EXIT
python3 "$mock" $port >/dev/null & srv=$!
for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 $srv 2>/dev/null || { echo "mock server failed to start"; exit 1; }; curl -s -o /dev/null "http://127.0.0.1:$port/api/v1/packages" && break; sleep 0.3; done
cd "$tmp"; mkdir lib; printf 'fake archive' > mylib-1.0.0.c3l

call() { printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$2"; }
# server <token> <write> : requests on stdin, responses on stdout
server() { env C3PKG_URL="http://127.0.0.1:$port" C3PKG_TOKEN="$1" C3PKG_WRITE="$2" "$bin" 2>/dev/null; }
expect() { printf '%s\n' "$out" | grep -q "$1" || { echo "FAIL: $2 (expected /$1/)"; printf '%s\n' "$out"; exit 1; }; echo "ok: $2"; }

# read-only, no token
out=$({ call search_packages '{"query":"v"}'
        call get_package '{"name":"vk"}'
        call list_versions '{"name":"vk"}'
        call download_package '{"name":"vk","dir":"newdir/sub"}'
        call download_package '{"name":"vk","version":"1.0.0","dir":"lib"}'
        call get_package '{"name":"ratelimit"}'
        call whoami '{}'
        call download_package '{"name":"badsum"}'
        call get_package '{"name":"redir"}'
        call download_package '{"name":"garbage"}'
        call download_package '{"name":"vk","dir":""}'
        call download_package '{"name":"vk","dir":"../x"}'
        call download_package '{"name":"vk","dir":"/tmp"}'
        call get_package '{"name":"../etc"}'; } | server "" 0)
expect '\\"total\\":1' "search filters by text"
expect 'Vulkan binding' "get_package"
expect 'sha256_file' "list_versions"
expect 'saved newdir/sub/vk-1.0.1.c3l' "download skips prerelease and yanked, creates dir"
[ -s newdir/sub/vk-1.0.1.c3l ] || { echo "FAIL: file not written"; exit 1; }
expect 'saved lib/vk-1.0.0.c3l' "explicit version"
expect 'HTTP 429' "rate limit is reported"
expect 'HTTP 401' "whoami without token fails"
expect 'checksum mismatch' "bad checksum rejected"
[ ! -e lib/badsum-1.0.0.c3l ] || { echo "FAIL: bad file was written"; exit 1; }
expect 'HTTP 302' "redirect is not followed"
expect 'unexpected response from registry' "non-JSON versions body"
expect 'dir must be a relative path' "empty, .. and absolute dir rejected"
expect 'invalid package name' "bad package name rejected"

# token, write disabled
out=$({ call whoami '{}'
        call star_package '{"name":"vk"}'
        call publish_package '{"name":"x","version":"1.0.0","file":"f","c3_version":"0.8.5"}'; } | server c3p_test 0)
expect 'login.*tester' "whoami with token"
expect 'stars.*1' "star_package"
expect '"error"' "publish hidden without C3PKG_WRITE"

# token, write enabled
out=$({ call publish_package '{"name":"mylib","version":"1.0.0","file":"mylib-1.0.0.c3l","c3_version":"0.8.5","description":"test lib"}'
        call publish_package '{"name":"mylib","version":"1.0.0","file":"mylib-1.0.0.c3l","c3_version":"0.8.5"}'
        call yank_version '{"name":"image","version":"0.0.6"}'
        call yank_version '{"name":"vk","version":"1.0.1"}'
        call yank_version '{"name":"vk","version":".."}'
        call publish_package '{"name":"x","version":"1.0.0","file":"/etc/passwd","c3_version":"0.8.5"}'
        call publish_package '{"name":"x","version":"1.0.0","file":"notes.txt","c3_version":"0.8.5"}'; } | server c3p_test 1)
expect 'created.*true' "publish creates package"
expect 'HTTP 409' "duplicate version rejected"
expect 'yanked.*true' "yank own version"
expect 'HTTP 403' "yank of foreign package refused"
expect 'invalid name or version' "bad version rejected"
expect 'file must be a relative .c3l path' "publish refuses absolute and non-.c3l files"
echo "e2e ok"
