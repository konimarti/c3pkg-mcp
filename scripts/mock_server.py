#!/usr/bin/env python3
"""In-memory stand-in for the c3pkg.eu API, for testing without network or a real token.

usage: scripts/mock_server.py [port]      (default 8765; token is "c3p_test")
Point the MCP server at it with C3PKG_URL=http://127.0.0.1:8765.
Special case: package "ratelimit" always answers 429.
"""
import hashlib, json, re, sys
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TOKEN = "c3p_test"
USER = "tester"

def blob(name, ver):
    return f"fake c3l {name} {ver}\n".encode() * 50

def version(name, ver, c3="0.8.5", yanked=False):
    data = blob(name, ver)
    return {"version": ver, "c3_version": c3, "targets": ["linux-x64", "macos-aarch64", "windows-x64"],
            "size": len(data), "sha256_file": hashlib.sha256(data).hexdigest(), "sha256_tree": "0" * 64,
            "yanked": yanked, "published": "2026-11-01T10:00:00Z",
            "download_url": f"/api/v1/packages/{name}/{ver}/download"}

def package(name, desc, tags, owner, vers, downloads=0):
    return {"name": name, "description": desc, "tags": tags, "owner": owner, "latest_version": vers[0] if vers else "",
            "c3_version": "0.8.5", "downloads": downloads, "stars": 0, "updated": "2026-11-01T10:00:00Z",
            "git_url": "", "created": "2026-10-01T10:00:00Z", "readme": f"# {name}\n\n{desc}\n",
            "versions": {v: version(name, v) for v in vers}}

PACKAGES = {p["name"]: p for p in [
    package("vk", "Vulkan binding for C3", ["gpu", "vulkan"], "alice", ["2.0.0-rc.1", "1.1.0", "1.0.1", "1.0.0"], 14),
    package("json", "JSON helpers", ["json", "encoding"], "bob", ["0.2.0"], 5),
    package("image", "Image loading", ["image"], USER, ["0.0.6"], 1),
    package("ratelimit", "always 429", [], "bob", ["1.0.0"]),
    package("badsum", "download does not match its checksum", [], "bob", ["1.0.0"]),
    package("redir", "always redirects", [], "bob", ["1.0.0"]),
    package("garbage", "versions endpoint returns HTML", [], "bob", ["1.0.0"]),
]}
PACKAGES["vk"]["versions"]["1.1.0"]["yanked"] = True
PACKAGES["vk"]["latest_version"] = "1.0.1"
STARS = set()

def summary(p):
    return {k: v for k, v in p.items() if k not in ("readme", "versions")}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send(self, status, obj=None, raw=None, headers=None):
        body = raw if raw is not None else (json.dumps(obj, separators=(",", ":")) + "\n").encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream" if raw is not None else "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items(): self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def err(self, status, msg): self.send(status, {"error": msg})

    def authed(self):
        if self.headers.get("Authorization") == f"Bearer {TOKEN}": return True
        self.err(401, "missing or invalid API token")
        return False

    def route(self, method):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        path = u.path
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        m = re.fullmatch(r"/api/v1/packages(?:/([^/]+))?(?:/([^/]+))?(?:/([^/]+))?(?:/([^/]+))?", path)
        if path == "/api/v1/me" and method == "GET":
            return self.authed() and self.send(200, {"login": USER, "name": "Test User"})
        if not m: return self.err(404, "not found")
        name, a, b, c = m.groups()
        if name == "ratelimit":
            return self.send(429, {"error": "rate limited"}, headers={"Retry-After": "7"})
        if name is None:
            if method != "GET": return self.err(405, "method not allowed")
            items = [summary(p) for p in PACKAGES.values()
                     if q.get("q", "") in p["name"] and (not q.get("tag") or q["tag"] in p["tags"])]
            key = {"downloads": lambda p: -p["downloads"], "stars": lambda p: -p["stars"]}.get(q.get("sort"), lambda p: p["name"])
            items.sort(key=key)
            per, page = min(int(q.get("per_page", 20)), 100), int(q.get("page", 1))
            return self.send(200, {"packages": items[(page - 1) * per: page * per], "page": page, "per_page": per, "total": len(items)})
        if name == "redir":
            return self.send(302, {}, headers={"Location": "http://127.0.0.1:1/elsewhere"})
        if name == "garbage" and a == "versions":
            return self.send(200, raw=b"<html>oops</html>")
        pkg = PACKAGES.get(name)
        # publish creates packages, so it is handled before the existence check
        if method == "PUT" and a == "versions" and b and c is None:
            return self.publish(name, b, body)
        if not pkg: return self.err(404, "package not found")
        if method == "GET" and a is None:
            return self.send(200, {**summary(pkg), "readme": pkg["readme"], "versions": list(pkg["versions"].values())})
        if method == "GET" and a == "versions" and b is None:
            return self.send(200, {"versions": list(pkg["versions"].values())})
        if method == "GET" and b == "download" and a in pkg["versions"]:
            pkg["downloads"] += 1
            return self.send(200, raw=b"tampered" if name == "badsum" else blob(name, a))
        if a == "star" and method in ("PUT", "DELETE"):
            if not self.authed(): return
            (STARS.add if method == "PUT" else STARS.discard)(name)
            pkg["stars"] = int(name in STARS)
            return self.send(200, {"stars": pkg["stars"]})
        if a == "versions" and c == "yank" and method in ("PUT", "DELETE"):
            if not self.authed(): return
            if pkg["owner"] != USER: return self.err(403, "not the owner")
            if b not in pkg["versions"]: return self.err(404, "version not found")
            pkg["versions"][b]["yanked"] = method == "PUT"
            return self.send(200, {"name": name, "version": b, "yanked": method == "PUT"})
        self.err(404, "not found")

    def publish(self, name, ver, body):
        if not self.authed(): return
        msg = BytesParser().parsebytes(b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + body)
        parts = {p.get_param("name", header="content-disposition"): p.get_payload(decode=True) for p in msg.get_payload()}
        if "file" not in parts or "c3_version" not in parts: return self.err(400, "file and c3_version are required")
        pkg = PACKAGES.get(name)
        created = pkg is None
        if created:
            if not parts.get("description"): return self.send(422, {"error": "validation failed", "errors": {"description": "required for a new package"}})
            pkg = PACKAGES[name] = package(name, parts["description"].decode(), [], USER, [])
        elif pkg["owner"] != USER: return self.err(403, "not the owner")
        if ver in pkg["versions"]: return self.err(409, "version already exists")
        pkg["versions"] = {ver: version(name, ver, parts["c3_version"].decode()), **pkg["versions"]}  # newest first
        pkg["latest_version"] = ver
        self.send(201, {"name": name, "version": ver, "created": created, "url": f"/packages/{name}"})

for m in ("GET", "PUT", "DELETE"):
    setattr(H, "do_" + m, lambda self, m=m: self.route(m))

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"mock c3pkg on http://127.0.0.1:{port} (token {TOKEN})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
