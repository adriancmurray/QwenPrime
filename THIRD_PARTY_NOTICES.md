# Third-party notices

Qwen Prime includes Sparkle 2 under the MIT License for application updates.
See https://github.com/sparkle-project/Sparkle.

Qwen Prime uses the official Model Context Protocol Swift SDK, whose source is
available under its MIT-to-Apache-2.0 licensing transition terms. Its resolved
Swift dependencies include EventSource (MIT) and Swift System, Swift Log, Swift
Atomics, Swift Collections, and SwiftNIO (Apache License 2.0). See
https://github.com/modelcontextprotocol/swift-sdk.

Qwen Prime uses swift-mcp-router's dependency-free Swift catalog ranking and
store components under the MIT License. See
https://github.com/adriancmurray/swift-mcp-router.

Qwen Prime does not include model weights in its source or application bundle.
Public builds may include the companion runtime and its licensed dependencies:

- Qwen3.8 model artifacts: Apache License 2.0. Distribute each artifact with its
  own `LICENSE`, `NOTICE`, provenance, and checksum files.
- MLX and MLX LM: MIT License.
- dflash-mlx: Apache License 2.0.
- Prime Agent: MIT License; independently installed from its upstream project.
- The macOS task sandbox profile is informed by Anthropic Sandbox Runtime,
  Apache License 2.0: https://github.com/anthropic-experimental/sandbox-runtime.

Qwen and the names of other third-party projects are trademarks of their
respective owners. Their inclusion here is attribution, not endorsement.
