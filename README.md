# Qwen Prime

Qwen Prime is a native Swift 6 and SwiftUI client for a local OpenAI-compatible
Qwen3.8 endpoint on Apple Silicon. It supports streaming responses, explicit
direct and reasoning modes, collapsible reasoning output, Markdown and code
rendering, persistent conversations, and local runtime health controls.

Workspace Agent mode can list and read files and propose bounded UTF-8 file
changes inside a user-authorized workspace. The agent pauses at each proposed
mutation while the app displays a diff. Apply or Reject resumes the same agent
run with the actual tool result. Agent mode can also propose a small allowlist
of argv-only workspace inspection commands. Approved commands run in an embedded
App-Sandboxed XPC helper with no network entitlement, bounded output, timeout,
and cancellation; arbitrary shell execution is not included.

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
Command execution is constrained to a narrow allowlist in a separately
sandboxed helper. It is not a general-purpose shell or operating-system sandbox.

## License and attribution

Qwen Prime is MIT licensed. See `THIRD_PARTY_NOTICES.md` for companion component
and model attribution. Qwen Prime is an independent project and is not affiliated
with or endorsed by the Qwen team, Apple, MLX, DFlash, or Prime Intellect.
