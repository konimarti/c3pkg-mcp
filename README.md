# c3pkg-mcp

An [MCP](https://modelcontextprotocol.io) server for the [c3pkg.eu](https://www.c3pkg.eu) package registry.
It lets an AI assistant find C3 libraries, read their documentation, check versions and checksums, and download them,
so it recommends libraries that exist and uses the right version.

## Install

Download the archive for your platform from the [Releases](../../releases) page and put `c3pkg-mcp` on your `PATH`.
Binaries are provided for Linux x64 (glibc 2.39+, e.g. Ubuntu 24.04), macOS arm64 and Windows x64. Linux needs `libcurl` (`sudo apt install libcurl4`); macOS has it already.

Or build from source (needs [c3c](https://github.com/c3lang/c3c) and [c3l](https://github.com/konimarti/c3l)):

```sh
c3l sync --frozen
c3c build -O1        # -> build/c3pkg-mcp
```

## Token

Create an API token at <https://www.c3pkg.eu/settings> (shown once, starts with `c3p_`) and pass it to the server as `C3PKG_TOKEN`.
Searching, reading and downloading work without it; `whoami`, `star_package` and the publishing tools need it.

| Variable | Meaning |
|---|---|
| `C3PKG_TOKEN` | API token |
| `C3PKG_WRITE=1` | Also enable `publish_package` and `yank_version` (off by default) |
| `C3PKG_URL` | Registry base URL (default `https://www.c3pkg.eu`) |

## Tools

| Tool | What it does |
|---|---|
| `search_packages` | Search by text and tag; sort by `latest`, `downloads` or `stars`; paginated |
| `get_package` | Description, owner, tags, links, README and versions |
| `list_versions` | Versions with C3 version, platforms, size, sha256 and yanked state |
| `download_package` | Save `<name>-<version>.c3l` into a directory (default `lib`) after verifying its sha256 |
| `whoami` | Show the account behind the token |
| `star_package` | Star or unstar a package |
| `publish_package` | Publish a relative-path `.c3l` as a new version, or create the package; public and permanent (needs `C3PKG_WRITE=1`) |
| `yank_version` | Yank or restore a version of your package (needs `C3PKG_WRITE=1`) |

Search and detail responses longer than 30 000 bytes are truncated. `download_package` and `publish_package` only accept relative paths without `..` (symlinks are not resolved, so do not point one outside the project); `download_package` creates the target directory. Registry errors (404, 429 rate limit, validation) are returned as-is. Redirects are not followed. Package READMEs and descriptions are third-party text: the assistant is told not to follow instructions found in them.
Published versions are immutable, so a publish cannot be undone, only yanked.

To add a library to a project, ask the assistant to run `c3l add <name>`; that records it in `c3l.lock`.
Use `download_package` when you only need the file.

## Use it with

Replace `/path/to/c3pkg-mcp` with the absolute path of the binary (on Windows, the path to `c3pkg-mcp.exe`).

**Claude Code**

```sh
claude mcp add c3pkg -e C3PKG_TOKEN=c3p_xxx -- /path/to/c3pkg-mcp
```

**Claude Desktop**: `claude_desktop_config.json`

```json
{ "mcpServers": { "c3pkg": { "command": "/path/to/c3pkg-mcp", "env": { "C3PKG_TOKEN": "c3p_xxx" } } } }
```

**VS Code** (GitHub Copilot agent mode): `.vscode/mcp.json`. The token is prompted for once and not stored in the file.

```json
{
  "inputs": [{ "id": "c3pkg-token", "type": "promptString", "description": "c3pkg API token", "password": true }],
  "servers": { "c3pkg": { "type": "stdio", "command": "/path/to/c3pkg-mcp", "env": { "C3PKG_TOKEN": "${input:c3pkg-token}" } } }
}
```

**Cursor**: `~/.cursor/mcp.json` uses the same format as Claude Desktop.

**Any other MCP client** that can launch a stdio server: command `c3pkg-mcp`, environment `C3PKG_TOKEN`.

## Examples

- "Find a C3 library for parsing JSON and tell me which versions work with c3c 0.8.5."
- "Show the README of `vk` and add the newest version to this project."
- "Which packages are most downloaded?"
- "Publish `./mylib-1.0.0.c3l` as `mylib` 1.0.0 (C3 0.8.5)." (with `C3PKG_WRITE=1`)

## Troubleshooting

- *"C3PKG_TOKEN is not set"* in the client's log: the token was not passed through the client's `env` setting.
- *HTTP 401 / 403*: the token is wrong, expired, or you do not own the package.
- *HTTP 429*: rate limited; wait and retry.
- The tools are missing: run `c3pkg-mcp --version` in a terminal to check the binary starts (on Linux a missing `libcurl` shows up here).
