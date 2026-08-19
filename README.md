# Qwen Prime

Qwen Prime is a native Swift 6 and SwiftUI client for a local OpenAI-compatible
Qwen3.8 endpoint on Apple Silicon. It supports streaming responses, explicit
direct and reasoning modes, collapsible reasoning output, Markdown and code
rendering, persistent conversations, and local runtime health controls.

Workspace Agent mode can list, discover, search, and read files, then propose
bounded UTF-8 file changes inside a user-authorized workspace. Recursive file
discovery and literal text search are result-, traversal-, and output-capped and
skip restricted paths, generated dependency/cache directories, opaque packages,
symlinks, and non-text content. The agent pauses at each proposed mutation while
the app displays a diff. Exact replacements across as many as eight existing
files can be grouped into one combined review; every file is checked for stale
content before the first write. Apply or Reject resumes the same agent
run with the actual tool result. Agent mode can also run generic argv-only
workspace processes after approval. The stable process substrate supports
bounded foreground execution plus supervised start, status, and stop operations
for long-running apps. Executables resolve from trusted macOS and Xcode tool
locations or from a workspace-relative built artifact; arguments are passed as
an array without Qwen Prime constructing a shell command string.

All processes run in the embedded App-Sandboxed XPC helper with no network
entitlement, workspace-scoped read/write access, bounded output, timeout, and
cancellation. Builds, tests, Git operations, directory creation, and launching a
built app use this same substrate instead of fixed per-language task tools. Agent
runs retain a bounded twelve-turn budget, and an approved mutation starts a new
workspace revision so the relevant process can be rerun against changed files.

Agent tools are assembled through a provider registry rather than wired
directly into the inference loop. The registry preserves provider identity and
per-tool approval metadata, rejects ambiguous duplicate names before inference,
and routes every call to its declaring provider. The built-in workspace tools
are the first provider. The MCP preview can discover tools from multiple
user-configured local Streamable HTTP servers. MCP tools are namespaced, every
call requires explicit one-shot approval, and an unavailable MCP server degrades
locally without disabling the other providers or built-in workspace tools.
Before inference, the registry uses the dependency-free Swift catalog ranker
from [`swift-mcp-router`](https://github.com/adriancmurray/swift-mcp-router) to
advertise a stable, bounded relevant tool set; explicit tool names always win,
and uncertain requests retain the complete catalog.

## Components

Qwen Prime is the UI. Public app builds bundle the Python inference runtime but
never bundle model weights. The companion
[`qwen-prime-runtime`](https://github.com/adriancmurray/qwen-prime-runtime)
project serves a hybrid Q8/Q4 Qwen3.8-27B target by default, with a matching
6-bit native MTP draft through MLX and `dflash-mlx`. Prime Agent is a separate
upstream project and can connect to the
same endpoint; it is not bundled or forked here.

## Requirements

- Apple Silicon Mac running macOS 14 or later
- Swift 6 toolchain
- A local Qwen3.8-27B MLX artifact and matching native MTP draft
- A source checkout of `qwen-prime-runtime` only when building the app yourself

## Model downloads

- Recommended target: [`adrianmurray/Qwen3.8-27B-Hybrid-Q8Q4`](https://huggingface.co/adrianmurray/Qwen3.8-27B-Hybrid-Q8Q4)
- Matching native-MTP draft: [`adrianmurray/Qwen3.8-27B-MTP-MLX-6bit`](https://huggingface.co/adrianmurray/Qwen3.8-27B-MTP-MLX-6bit)

Download both repositories to local folders, then select those folders in
**Settings → Engine & MLX**. The app does not download or bundle model weights.

## Build

```bash
git clone https://github.com/adriancmurray/QwenPrime.git
cd QwenPrime
./package_app.sh
open QwenPrime.app
```

The app connects only to `http://127.0.0.1:8000/v1` by default. Public builds
include the runtime. Choose the target and draft directories in **Settings →
Engine & MLX**; Qwen Prime saves those paths in Application Support, validates
the pair, and starts the local server.

For a source build without an embedded runtime, configure and start the
companion command before opening the app:

```bash
qwen-prime-runtime configure \
  --target /path/to/Qwen3.8-27B-Hybrid-Q8Q4 \
  --draft /path/to/Qwen3.8-27B-MTP-MLX-6bit
qwen-prime-runtime doctor
qwen-prime-runtime serve
```

`setup.sh` can install the companion runtime from a local checkout, merge the
provider into an existing Prime Agent configuration without replacing other
providers, and package the app:

```bash
QWEN_PRIME_RUNTIME_SOURCE=/path/to/qwen-prime-runtime \
./setup.sh /path/to/Qwen3.8-27B-Hybrid-Q8Q4 \
  /path/to/Qwen3.8-27B-MTP-MLX-6bit
```

## Local MCP tools (preview)

Open **Settings → General → Local MCP Servers** and add one or more Streamable
HTTP endpoints listening on `localhost`, `127.0.0.1`, or `::1`. Each server can
be enabled independently. **Test Connection** verifies the endpoint and shows
its discovered tool catalog before an Agent run. Qwen Prime refreshes enabled
servers at the start of each Agent run and exposes their tools as
`mcp__<provider>__<tool>` names. It does not send MCP roots or the selected
workspace path during connection. Each external tool call pauses in the same
floating review surface used by native workspace actions and runs only after
**Allow Once**. Disabling or removing a server leaves native Agent tools and
other MCP servers unchanged.

### Tool-routing benchmark

Development builds include a paired switch for measuring the same Agent prompt
with semantic tool reduction enabled or with the complete catalog. Package and
open the app once, switch either mode without restarting the app or model, then
inspect the routing line after each run:

```bash
./benchmark_tool_routing.command full
./benchmark_tool_routing.command ranked
./benchmark_tool_routing.command report
```

The result reports advertised versus available tool counts and estimated schema
tokens. The message footer reports server prefill time, generated tokens, and
decode throughput. Use a new conversation for each mode and the same prompt.

## Workspace instructions (preview)

Agent mode automatically loads a regular UTF-8 `AGENTS.md` from the selected
workspace root. The loaded instructions appear as a Workspace Instructions card
in the conversation, and the behavior can be disabled in **Settings → General →
Workspace Instructions**. Nested instruction files are intentionally outside the
v1 scope. Symlinked, binary, and oversized files are ignored. Workspace
instructions and explicit skills share a 32 KiB prompt budget and do not grant
additional tools, access, or approval authority.

## Agent skills (preview)

Qwen Prime discovers standard `SKILL.md` packages from
`<workspace>/.qwenprime/skills/<package>/SKILL.md` and
`~/Library/Application Support/QwenPrime/skills/<package>/SKILL.md`. Open
**Settings → General → Agent Skills** to refresh and enable individual skills.
Enabled skills are still loaded only when the prompt explicitly names them,
for example `$swift-review`. Each loaded skill appears in the conversation as a
Skill card so the run's added context is visible.

Skills v1 loads only the selected `SKILL.md` instructions. It does not execute
bundled scripts, read referenced files, add tools, expand workspace or network
access, or bypass an approval. Symlinked and oversized skill files are ignored;
each run accepts at most four skills within a bounded prompt budget.

## Release packaging

`package_app.sh` creates and verifies a local app bundle. It uses ad-hoc signing
unless `DEVELOPER_ID_APPLICATION` names an installed signing identity.
`release_app.command` requires a Developer ID identity, creates a ZIP, can
notarize it with either `NOTARY_PROFILE` or an Apple ID, team ID, and
app-specific password, and writes a SHA-256 checksum.

Public builds use Sparkle 2 for user-initiated updates. Automatic background
checks are disabled: updates are requested from the app menu or Quick Settings.
GitHub hosts `appcast.xml` and the signed release archives, so no separate
update service or administration application is required. Public packaging
requires `SPARKLE_PUBLIC_ED_KEY`; `SPARKLE_FEED_URL` defaults to this
repository's raw `appcast.xml` URL.

The runtime updates atomically with the app without bundling model weights.
`release_app.command` builds the locked relocatable payload automatically from
a sibling `qwen-prime-runtime` checkout. Set `QWEN_PRIME_RUNTIME_SOURCE` to an
explicit verified checkout when it lives elsewhere; packaging fails rather than
silently selecting a legacy harness checkout. To package an existing payload, set
`QWEN_PRIME_EMBEDDED_RUNTIME`; the payload is copied to
`QwenPrime.app/Contents/Resources/QwenPrimeRuntime`; user model paths remain in
Application Support and survive app replacement.

After the one-time Developer ID, notarization, and Sparkle signing credentials
are configured, a release is published locally with:

```bash
./publish_release.command 1.1.1
```

The command refuses a dirty worktree, builds and notarizes the app, signs the
Sparkle update from an injected private key, commits the updated appcast, tags
and pushes the release, and uploads the archive and checksum to GitHub Releases.
Run `./release_preflight.command 1.1.1` at any time to verify the non-secret
release prerequisites. It lists Apple, Sparkle, and GitHub credentials as one
deferred final checkpoint without reading or printing their values.

See [`docs/PUBLISHING.md`](docs/PUBLISHING.md) for the initial two-repository,
two-model publication order and the shorter recurring update workflow.

Measured throughput depends on hardware, prompt shape, thermals, context length,
and draft acceptance. On the development M4 Max, the downloaded Qwen Prime 1.1.1
application measured 29.38 server tokens/second with 55.9% draft acceptance on
a 256-token Swift task using the hybrid target. This is an observation, not a
guaranteed minimum.

## Security boundary

The inference endpoint is intended for loopback use. Do not expose it to a LAN
or the internet without adding authentication and transport security. Workspace
Agent access is confined to the user-authorized folder, rejects symlink escapes
and sensitive paths, and requires approval for text mutations and process
execution. The generic argv-only process helper is separately App-Sandboxed,
network-disabled, bounded in time and output, and limited to the authorized
workspace plus trusted system tool locations. Qwen Prime does not interpret
shell command strings. MCP connections are restricted to loopback Streamable
HTTP endpoints, share no workspace roots automatically, and require approval
before every external tool call.

## License and attribution

Qwen Prime is MIT licensed. See `THIRD_PARTY_NOTICES.md` for companion component
and model attribution. Qwen Prime is an independent project and is not affiliated
with or endorsed by the Qwen team, Apple, MLX, DFlash, or Prime Intellect.
