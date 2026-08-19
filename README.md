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
run with the actual tool result. Agent mode can also propose a small allowlist
of argv-only workspace inspection commands. Approved commands run in an embedded
App-Sandboxed XPC helper with no network entitlement, bounded output, timeout,
and cancellation. The initial surface includes `pwd`, flag-only `ls`, and
hardened fixed-form Git metadata inspection (`log` and `rev-parse`); arbitrary
shell execution is not included.

Approved Swift build and test tasks run through the bundled `QwenPrimeHarness`,
an independent Swift executable with a versioned typed protocol. The app first
copies a bounded text-only package into an app-owned task directory. The harness
then runs fixed-form `swift build` or `swift test` operations inside a
deny-by-default, network-disabled Seatbelt profile. The task tool is advertised
only after the bundled harness passes an automatic sandboxed self-test; file and
inspection tools remain available if that check fails. A read-only task catalog
reports the fixed task IDs and discovers bounded `Package.swift` working
directories, so agents do not need to probe a workspace one folder at a time.
Agent runs have a bounded twelve-turn budget for practical inspect, edit,
build/test, and retry cycles. The duplicate-call guard remains active within a
workspace revision, but an approved mutation starts a new revision so the same
fixed test task can be rerun against the changed files.

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
notarize it when `NOTARY_PROFILE` is set, and writes a SHA-256 checksum.

Public builds use Sparkle 2 for user-initiated updates. Automatic background
checks are disabled: updates are requested from the app menu or Quick Settings.
GitHub hosts `appcast.xml` and the signed release archives, so no separate
update service or administration application is required. Public packaging
requires `SPARKLE_PUBLIC_ED_KEY`; `SPARKLE_FEED_URL` defaults to this
repository's raw `appcast.xml` URL.

The runtime updates atomically with the app without bundling model weights.
`release_app.command` builds the locked relocatable payload automatically from
the sibling `local-eval-harness` checkout. Set `QWEN_PRIME_RUNTIME_SOURCE` when
that checkout lives elsewhere. To package an existing payload manually, set
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
and draft acceptance. Development measurements around 26 server tokens/second
and 28 tokens/second in a block-size sweep are observations, not guarantees.

## Security boundary

The inference endpoint is intended for loopback use. Do not expose it to a LAN
or the internet without adding authentication and transport security. Workspace
Agent access is confined to the user-authorized folder, rejects symlink escapes
and sensitive paths, and requires approval for text mutations and commands.
Inspection command execution is constrained to a narrow allowlist in a
separately App-Sandboxed helper. Swift build and test tasks use the independent
Swift harness against a staged package with isolated caches, bounded output and
time, no network, and writes limited to the task root. Neither path is a
general-purpose shell. MCP connections are restricted to loopback Streamable
HTTP endpoints, share no workspace roots automatically, and require approval
before every external tool call.

## License and attribution

Qwen Prime is MIT licensed. See `THIRD_PARTY_NOTICES.md` for companion component
and model attribution. Qwen Prime is an independent project and is not affiliated
with or endorsed by the Qwen team, Apple, MLX, DFlash, or Prime Intellect.
