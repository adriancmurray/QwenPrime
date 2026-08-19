# Publishing Qwen Prime

Qwen Prime has four required, independently reviewable release units:

1. `adrianmurray/Qwen3.8-27B-Hybrid-Q8Q4` on Hugging Face: recommended target weights.
2. `adrianmurray/Qwen3.8-27B-MTP-MLX-6bit` on Hugging Face: matching native-MTP draft.
3. `adriancmurray/qwen-prime-runtime` on GitHub: runtime source and wheel.
4. `adriancmurray/QwenPrime` on GitHub: source, Sparkle appcast, and notarized app archive.

`adrianmurray/Qwen3.8-27B-MLX-6bit` remains available as the uniform 6-bit
baseline and optional target.

The model repositories are not downloaded automatically. The app asks the user
to choose both folders and stores only their paths in
`~/Library/Application Support/QwenPrime/runtime.json`. The Python runtime is
embedded in every public app archive and therefore updates with Sparkle.

## Non-secret preflight

From the QwenPrime checkout:

```bash
swift package resolve
./release_preflight.command 1.1.1
```

The preflight validates local tools, Sparkle artifacts, the appcast, and release
scripts. It reports credential names but never reads or prints their values.

From the runtime checkout:

```bash
uv sync --extra dev
uv run pytest
uv build --wheel
./scripts/build_embedded_runtime.command /private/tmp/QwenPrimeRuntime
/private/tmp/QwenPrimeRuntime/bin/qwen-prime-runtime --help
```

Move the payload before the final command when testing relocation. Run `doctor`
with the release model pair selected.

## Final credential checkpoint

Keep these values outside the repositories and inject them only into the final
release command:

- `DEVELOPER_ID_APPLICATION`: the Developer ID Application identity name.
- `NOTARY_PROFILE`: an Apple `notarytool` profile name.
- `SPARKLE_PUBLIC_ED_KEY`: the public Sparkle Ed25519 key embedded in the app.
- `SPARKLE_PRIVATE_KEY`: the matching private seed used only by
  `generate_appcast --ed-key-file -`.
- GitHub CLI authorization with repository and release access.
- `HF_TOKEN` with write access to the model repositories.

Do not put private values in shell history, source files, app resources,
appcasts, logs, or GitHub Actions output. Qwen Prime's publishing script accepts
the Sparkle private key through standard input and does not create a key file.

## Initial publication order

1. Create the two Hugging Face model repositories and upload each verified
   directory with `hf upload-large-folder`.
2. Publish the curated runtime source and wheel to
   `adriancmurray/qwen-prime-runtime`.
3. Publish the prepared QwenPrime source.
4. Inject the Apple, Sparkle, and GitHub values and run:

   ```bash
   ./publish_release.command 1.1.1
   ```

The command requires committed source, builds the locked embedded runtime,
signs the complete app with hardened runtime, notarizes and staples it, creates
the archive and checksum, signs the Sparkle appcast, commits that appcast, tags
the release, pushes it, and creates the GitHub Release.

## Future app and runtime updates

Update the app and/or runtime source, update the locked dependency versions,
run both test suites and the non-secret preflight, then run
`publish_release.command` with a new semantic version. No Cloudflare worker,
Studio Admin deployment, or secondary update monitor is involved. Sparkle reads
the GitHub-hosted appcast only when the user presses **Check for Updates**.

Model artifacts need a new revision only when their actual weights or metadata
change. Ordinary app and runtime releases continue using the model paths already
stored in Application Support.
