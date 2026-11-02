#!/bin/sh
# Test every tool against a real c3pkg registry running locally (Docker), including publish and yank.
# usage: scripts/registry_test.sh [build/c3pkg-mcp]
#   REGISTRY_URL=http://host:port  use an already running registry instead of starting the container
#   C3PKG_REF=<commit>             upstream commit to build (default: the pinned one)
set -eu
bin=$(realpath "${1:-build/c3pkg-mcp}")
compose="$(realpath "$(dirname "$0")/../test/registry/compose.yml")"
url=${REGISTRY_URL:-http://127.0.0.1:18080}
work=$(mktemp -d)
started=0
cleanup() { [ "$started" = 1 ] && docker compose -f "$compose" down -v >/dev/null 2>&1; rm -rf "$work"; }
trap cleanup EXIT

if [ -z "${REGISTRY_URL:-}" ]; then
  started=1
  docker compose -f "$compose" up -d --build --wait
fi
curl -fsS "$url/healthz" >/dev/null || { echo "registry not reachable at $url"; exit 1; }

# 1. account and API token (tokens can only be created from a browser session)
jar="$work/jar"; id="t$(date +%s)"
curl -fsS -c "$jar" -b "$jar" "$url/register" -o /dev/null
csrf=$(awk '$6=="c3_csrf"{print $7}' "$jar")
curl -fsS -c "$jar" -b "$jar" -o /dev/null --data-urlencode "csrf=$csrf" --data-urlencode "email=$id@example.com" \
  --data-urlencode "login=$id" --data-urlencode "name=MCP Test" \
  --data-urlencode "password=correct-horse-battery" --data-urlencode "confirm=correct-horse-battery" "$url/register"
token=$(curl -fsS -c "$jar" -b "$jar" -H "X-CSRF-Token: $csrf" -H 'Content-Type: application/json' \
  -d '{"name":"mcp-test"}' "$url/api/v1/me/tokens" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$token" ] || { echo "could not create an API token"; exit 1; }

# 2. a minimal valid library per version, as a .c3l (zip with manifest.json at the root; its version must match the upload)
pkg="mcptest-$id"
cd "$work"
python3 -I - "$pkg" 0.1.0 0.2.0-rc.1 <<'PY'
import sys, zipfile
name, versions = sys.argv[1], sys.argv[2:]
for v in versions:
    with zipfile.ZipFile(f"{name}-{v}.c3l", "w") as z:
        z.writestr("manifest.json", '{"provides": "%s", "version": "%s", "sources": ["src/**"]}' % (name, v))
        z.writestr("src/lib.c3", "module %s;\nfn int one() => 1;\n" % name.replace("-", "_"))
PY
mkdir lib

call() { printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$2"; }
expect() { printf '%s\n' "$out" | grep -q "$1" || { echo "FAIL: $2 (expected /$1/)"; printf '%s\n' "$out"; exit 1; }; echo "ok: $2"; }

# 3. run the tools against the real server
out=$({ call whoami '{}'
        call publish_package "{\"name\":\"$pkg\",\"version\":\"0.1.0\",\"file\":\"$pkg-0.1.0.c3l\",\"c3_version\":\"0.8.5\",\"description\":\"mcp test\",\"tags\":\"test\",\"license\":\"MIT\"}"
        call publish_package "{\"name\":\"$pkg\",\"version\":\"0.1.0\",\"file\":\"$pkg-0.1.0.c3l\",\"c3_version\":\"0.8.5\"}"
        call publish_package "{\"name\":\"$pkg\",\"version\":\"0.2.0-rc.1\",\"file\":\"$pkg-0.2.0-rc.1.c3l\",\"c3_version\":\"0.8.5\"}"
        call search_packages "{\"query\":\"$pkg\"}"
        call get_package "{\"name\":\"$pkg\"}"
        call list_versions "{\"name\":\"$pkg\"}"
        call download_package "{\"name\":\"$pkg\"}"
        call star_package "{\"name\":\"$pkg\"}"
        call star_package "{\"name\":\"$pkg\",\"star\":false}"
        call yank_version "{\"name\":\"$pkg\",\"version\":\"0.1.0\"}"
        call download_package "{\"name\":\"$pkg\"}"
        call yank_version "{\"name\":\"$pkg\",\"version\":\"0.1.0\",\"yank\":false}"
        call download_package "{\"name\":\"$pkg\"}"; } \
  | env C3PKG_URL="$url" C3PKG_TOKEN="$token" C3PKG_WRITE=1 "$bin" 2>/dev/null)
expect "login.*$id" "whoami"
expect 'created.*true.*0.1.0' "publish creates the package"
expect 'HTTP 409' "republishing a version is refused"
expect 'created.*false.*0.2.0-rc.1' "prerelease published as a new version"
expect "name.*$pkg.*total.*1" "search finds it"
expect "license.*MIT" "get_package"
expect 'sha256_file' "list_versions"
expect "saved lib/$pkg-0.1.0.c3l" "download skips the prerelease"
[ -s "lib/$pkg-0.1.0.c3l" ] && cmp -s "lib/$pkg-0.1.0.c3l" "$pkg-0.1.0.c3l" || { echo "FAIL: downloaded file differs from the upload"; exit 1; }
expect 'starred.*true.*stars.*1' "star"
expect 'starred.*false.*stars.*0' "unstar"
expect 'no stable, non-yanked version' "a yanked version is not downloaded by default"
expect "saved lib/$pkg-0.1.0.c3l.*" "unyank makes it downloadable again"
echo "registry test ok"
