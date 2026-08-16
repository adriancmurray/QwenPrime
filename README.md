# Qwen Prime 🔮

A modern, native macOS application crafted with Swift 6 and SwiftUI, purpose-built for chatting and coding with local **Qwen 3.8 27B** models accelerated by Apple Silicon MLX and speculative decoding.

![macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![MLX Powered](https://img.shields.io/badge/Engine-Apple%20Silicon%20MLX-purple)
![License MIT](https://img.shields.io/badge/license-MIT-green)

---

## ✨ Features

- ⚡ **Ultra-Fast Local Streaming:** Direct async SSE streaming to local MLX inference engines (`http://127.0.0.1:8000/v1`) with sub-15ms Time-to-First-Token.
- 🧠 **Live Chain-of-Thought (CoT):** Real-time collapsible `<think>` reasoning accordions with token counters and live generation timers.
- 🎨 **Extensible Markdown Themes:** 5 switchable themes built-in:
  - **Prime Dark** (Default cyan & indigo tech)
  - **Cyberpunk Neon** (Vivid yellow & pink)
  - **Dracula** (Classic purple & cyan)
  - **Nordic Frost** (Icy arctic blue & slate)
  - **Monochrome Studio** (High-contrast studio black & white)
- 📦 **Workspace & Sandboxing:** Directory-scoped project switching (`~/prime-sandbox`, `~/projects/`), with quick actions to reveal in Finder or open in Terminal.
- 🪄 **Codex / Antigravity Style Input Card:** Floating multi-line input card with aligned send actions, workspace picker chips, and model status badges.
- 🗂 **Persistent Conversations:** Automatically saves and reloads conversations locally with full search, date groupings (*Today*, *Yesterday*, *Previous 7 Days*), duplicate support, and export to Markdown (`.md`).
- 🛑 **Safe Engine Control:** Two-step engine lifecycle management in the window titlebar to start, stop (free GPU memory), or restart the local model daemon.

---

## 🚀 Quick Start

### 1. Build & Run from Source

```bash
# Clone the repository
git clone https://github.com/adrian/QwenPrime.git
cd QwenPrime

# Build and package the standalone macOS app
./package_app.sh

# Launch the app
open QwenPrime.app
```

### 2. Connect Your Local MLX Model

Qwen Prime connects by default to OpenAI-compatible endpoints at `http://127.0.0.1:8000/v1`. 

You can launch the resident server using `mlx-lm` or the DFlash speculative bridge:

```bash
# Example with standard MLX LM
python -m mlx_lm.server --model path/to/Qwen3.8-27B-MLX-6bit --port 8000
```

---

## 🛠 Architecture

```
Sources/QwenPrime/
├── App/                # App entrypoint & keyboard shortcuts (⌘N, ⌘K, ⌘,)
├── Models/             # Conversation, ChatMessage, GenerationStats, MarkdownTheme
├── Services/           # Actor-safe QwenClient (SSE), StorageService, ServerHealthService
├── ViewModels/         # AppState (global observable state), ChatViewModel
└── Views/
    ├── Sidebar/        # Workspace picker, Search, Conversation rows with swipe actions
    ├── Chat/           # MessageBubble, MarkdownView, CodeBlockView, PromptInputBar
    └── Settings/       # Server configuration & model parameters
```

---

## 📄 License

MIT License © 2026. Free for personal, open-source, and commercial use.
