# LLM-Manager

A lightweight, modular Bash orchestration suite to manage, start, stop, and monitor local and remote LLM inference engines (Ollama, Llama.cpp) with a dual interactive/JSON interface.

Developed primarily to solve the complexity of managing ibrid environments (like Windows hosts from WSL2) and remote deployments via SSH without the overhead of heavy Python or dashboard solutions.

## Key Features

- **Multi-Engine Support:** Native orchestration for `ollama` and `llama.cpp` (with `vLLM` planned).
- **Cross-Platform & Hybrid Environments:** Supports native Linux, WSL2, and Windows hosts (orchestrating Windows processes from WSL2 using PowerShell bridges only when necessary, such as starting servers).
- **Remote Proxying via SSH:** `engine-run.sh` can act as a local proxy, forwarding actions securely to remote servers.
- **Dual Output Contract:** Prints clean, interactive text to `stderr` for human operators, and structured **JSON to `stdout`** for easy parsing by remote tools, scripts, or Web UIs.
- **Dynamic Modelfile Generation:** Automatically builds Ollama `Modelfiles` from local GGUF models on the fly.

---

## Project Structure

```text
.
├── engine.conf               # Global configuration and constants
├── engine-models.json        # Model registry with per-engine metadata
├── engine-templates.json     # Prompt/Model templates by family
├── engine-run.sh             # Main orchestrator & entry-point
├── engine-common.sh          # OS detection, process management, JSON formatting
├── engine-config.sh          # Config summary and model listing
├── engine-status.sh          # Cross-engine status aggregation & metrics
├── engine-system.sh          # OS-level hardware metrics (CPU, RAM, GPU, Disk)
├── logs/                     # Log directory
├── llama/                    # Llama.cpp specific scripts
└── ollama/                   # Ollama specific scripts

```

Each engine subdirectory implements a consistent layout:

* `start.sh` / `stop.sh` — Manage the server lifecycle.
* `status.sh` — Check running state and active models.
* `load.sh` / `unload.sh` — Load models into VRAM/RAM or release them.
* `show.sh` / `remove.sh` — Inspect or delete models.

---

## Quick Start & Usage

### 1. Configuration

Copy and tweak your global settings in `engine.conf`:

```bash
OS_TYPE="wsl" # "wsl" or "linux"
BASE_DIR="/mnt/c/LLM/engines"

# Windows directory mandatory for wsl
WIN_DIR="/mnt/c/Windows"

MODELS_ROOT="/mnt/c/Models"
VALID_ENGINES="ollama llama"

```

### 2. Run the Orchestrator

Running the script without arguments displays the interactive help alongside the JSON error contract:

```bash
./engine-run.sh

```

**Interactive Output:**

```text
Error: LLM Manager
Usage: engine-run.sh <action> [engine] [args...]
actions:
    config                           Global config
    models [-h]                      List available models (-h human readable)
    status <engine>                  Show global or engine status
    start <engine> [model] [users]   Start an engine
    stop <engine>                    Stop an engine
    load <engine> [model] [users]    Load a model
    unload <engine> <model>          Unload a model
    show <engine> <model>            Show engine details
    remove <engine> <model>          Remove a model and engine

```

### 3. Get System & Engine Status

```bash
./engine-run.sh status

```

This aggregates hardware metrics (CPU load, RAM, GPU VRAM availability, Disk space) and queries running engines, returning a comprehensive JSON payload.

---

## Model Loading Strategies (`engine-models.json`)

The manager abstracts how models are handled via three loader strategies defined per model:

* `native`: Pulls and runs the model directly from the engine's official registry (e.g., Ollama library).
* `gguf`: Handles raw `.gguf` files. For Ollama, the manager dynamically generates the required `Modelfile` on load, mapping templates automatically.
* `auto`: Uses the local GGUF file if present; otherwise, falls back to a native registry pull.

*Advanced features like multimodal setups (`mmproj`) and speculative decoding (`draft_model` for llama.cpp) are supported natively through configuration.*

---

## Future Work / Roadmap

* Complete vLLM engine integration.
* Implement an SSH security sandbox (ForceCommand validation).
* Refactor startup health-checks from fixed `sleep` intervals to proactive retry loops.

## License

This project is open-source and available under the [MIT License](https://www.google.com/search?q=LICENSE).

---
