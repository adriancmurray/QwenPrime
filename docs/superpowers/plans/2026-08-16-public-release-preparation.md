# Qwen Prime Public Release Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a self-contained, publicly distributable Qwen Prime app whose inference runtime updates with the app while user-supplied Qwen3.8 model weights remain external and persistent.

**Architecture:** The app bundle owns a relocatable CPython runtime and locked `qwen-prime-runtime` environment under `Contents/Resources/QwenPrimeRuntime`. A small Swift service owns the user model-path configuration in Application Support and the Engine settings UI validates both artifacts before starting the loopback server. Sparkle, Developer ID signing, notarization, and GitHub Releases remain a final credentialed publication boundary.

**Tech Stack:** Swift 6, SwiftUI, Swift Package Manager, Sparkle 2.9.3, CPython 3.12, uv, MLX, dflash-mlx, GitHub Releases.

## Global Constraints

- Support Apple Silicon and macOS 14 or later.
- Use Qwen3.8-27B target and matching native-MTP draft, both MLX 6-bit.
- Do not bundle model weights.
- Bind the inference server to loopback by default.
- Do not store or print Apple, notarization, Sparkle, or GitHub credentials.
- Defer all credentialed operations to one final checkpoint.
- Preserve the existing approved work in the current shared checkout.

Paths below use `$QWEN_PRIME_APP_ROOT` for the QwenPrime checkout and
`$QWEN_PRIME_RUNTIME_ROOT` for the qwen-prime-runtime checkout.

---

### Task 1: Relocatable runtime payload

**Files:**
- Create: `$QWEN_PRIME_RUNTIME_ROOT/scripts/build_embedded_runtime.command`
- Modify: `$QWEN_PRIME_RUNTIME_ROOT/docs/RELEASE.md`
- Test: `$QWEN_PRIME_RUNTIME_ROOT/tests/test_embedded_runtime.py`

**Interfaces:**
- Consumes: the locked `qwen-prime-runtime` project and uv-managed CPython 3.12.
- Produces: a directory containing executable `bin/qwen-prime-runtime`, `python/`, and a relocatable environment whose launcher resolves all paths relative to itself.

- [ ] Add a failing structural test that verifies the launcher contains no source-checkout path and still runs after the payload directory is moved.
- [ ] Run the focused test and confirm it fails because the builder does not exist.
- [ ] Add the minimum builder and relative launcher; sync from `uv.lock` without development or training extras.
- [ ] Build the payload, move it to a second temporary directory, and run `qwen-prime-runtime --help` and `doctor` there.
- [ ] Run the runtime test suite and inspect the payload for excluded source, caches, tests, and model files.

### Task 2: Model setup and validation

**Files:**
- Create: `$QWEN_PRIME_APP_ROOT/Sources/QwenPrime/Models/RuntimeConfiguration.swift`
- Create: `$QWEN_PRIME_APP_ROOT/Sources/QwenPrime/Services/RuntimeConfigurationService.swift`
- Modify: `$QWEN_PRIME_APP_ROOT/Sources/QwenPrime/ViewModels/AppState.swift`
- Modify: `$QWEN_PRIME_APP_ROOT/Sources/QwenPrime/Views/Settings/SettingsView.swift`
- Test: `$QWEN_PRIME_APP_ROOT/Tests/QwenPrimeTests/QwenPrimeTests.swift`

**Interfaces:**
- Produces: `RuntimeConfiguration(targetModelPath:draftModelPath:)`, atomic load/save, directory selection, and `qwen-prime-runtime doctor` validation surfaced in Engine settings.
- Consumes: `ServerHealthService` for runtime discovery and lifecycle.

- [ ] Add tests for JSON round-trip, atomic persistence, missing directories, and executable lookup.
- [ ] Run the focused Swift tests and confirm the new behavior is absent.
- [ ] Implement the configuration service without duplicating model-provenance validation.
- [ ] Replace the stale hard-coded drafter description with selectable target/draft paths, setup status, validation, and clear recovery actions.
- [ ] Ensure app startup does not repeatedly attempt to launch an unconfigured runtime and routes the user to Engine settings.
- [ ] Run all Swift tests.

### Task 3: App packaging integration

**Files:**
- Modify: `$QWEN_PRIME_APP_ROOT/package_app.sh`
- Create: `$QWEN_PRIME_APP_ROOT/build_embedded_runtime.command`
- Modify: `$QWEN_PRIME_APP_ROOT/README.md`

**Interfaces:**
- Produces: a packaged app containing the versioned runtime payload and no model weights.

- [ ] Add package preflight checks for runtime launcher, Python executable, architecture, and forbidden model artifacts.
- [ ] Build the runtime through the companion checkout and package it by default for release builds.
- [ ] Verify bundle-relative execution from `QwenPrime.app/Contents/Resources/QwenPrimeRuntime`.
- [ ] Document source builds, runtime-only builds, and public release builds distinctly.

### Task 4: Credential-free release hardening

**Files:**
- Modify: `$QWEN_PRIME_APP_ROOT/release_app.command`
- Modify: `$QWEN_PRIME_APP_ROOT/publish_release.command`
- Create: `$QWEN_PRIME_APP_ROOT/release_preflight.command`
- Modify: `$QWEN_PRIME_APP_ROOT/README.md`
- Modify: `$QWEN_PRIME_APP_ROOT/THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Produces: a read-only preflight, a signed/notarized archive command, and an explicit publishing command that accepts credentials only through environment injection.

- [ ] Add dry-run and preflight coverage for version/build metadata, runtime presence, Sparkle configuration, Git state, archive names, and required tools.
- [ ] Ensure release scripts never invoke Keychain discovery or print secret values.
- [ ] Ensure appcast generation, commit, tag, push, and GitHub upload occur only in the explicit publish command.
- [ ] Document the one-time credential checklist as the final boundary.

### Task 5: End-to-end acceptance

**Files:**
- Modify only files implicated by verification failures.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: evidence that the app and relocated runtime are ready for the single credentialed publication pass.

- [ ] Run the full Swift test suite and runtime Python test suite.
- [ ] Build the embedded runtime and relocate it before exercising the CLI.
- [ ] Package the app and verify its signature, framework linkage, Info.plist, icon, licenses, and absence of model weights.
- [ ] Launch a fresh exact app bundle and verify model setup, start/stop, direct mode, reasoning mode, sidebar background activity, and update-button availability behavior.
- [ ] Run release preflight without credentials and confirm it reports only the deferred credential requirements.
- [ ] Review the final diff and report the single credential checkpoint plus exact publication command; do not publish without explicit authorization.
