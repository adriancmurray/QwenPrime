# Qwen Prime Harness donor audit

QwenPrimeHarness is an independent Swift implementation inside this repository.
The projects below were inspected read-only for architectural patterns; they are
not modified, copied wholesale, or added as dependencies.

- AgentHarnessKit: versioned envelopes, credential redaction, runner supervision,
  and MCP catalog separation. The worktree was dirty and no clear top-level
  license was found, so no source was copied.
- Niru: typed scoped-execution requests, client factories, and smoke checks. It
  remains an independent app-shaped harness.
- StudioRunnerCore: bounded process capture, cancellation, Swift package
  discovery, and owned scratch paths. It remains owned by StudioWorkspace.
- Cavorite Harness: orchestration reference only; it is Rust and solves a
  different multi-agent coordination problem.
- Pavilion / CanvasAgentKit: semantic UI automation and acceptance tooling, not
  process execution.

QwenPrimeHarness owns only Qwen Prime's typed local tool execution boundary.
It does not own inference, conversation persistence, UI automation, or general
multi-agent orchestration.
