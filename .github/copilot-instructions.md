# Local LLM Manager

## Overview
Management system for local and remote engines running open-source LLMs.
Entirely written in Bash.

## Supported Engines
- **ollama** — multi-model server with REST API
- **llama.cpp** — single-model server (llama-server)
- **vLLM** — (planned, stub only)

## Supported Environments
- Engine on a **Windows host** (managed via PowerShell from WSL2)
** Use powershell only if needed. I think it is necessary only for starting the server **
- Engine on **WSL2** or native **Linux**
- **Remote SSH**: `engine-run.sh` acts as a local proxy, SSH-calling the remote server

## Architecture

### Entry Point
- `engine-run.sh` — Orchestrator; validates action/engine args against whitelists, routes to engine-specific scripts;

### Shared Libraries
- `engine-common.sh` — OS detection, config loading, binary/GGUF discovery, JSON output formatting, process management, logging
- `engine-config.sh` — Configuration summary and model listing with filter support
- `engine-status.sh` — Cross-engine status aggregation + system metrics
- `engine-system.sh` — Memory, GPU (engine-agnostic), disk, CPU info

### Configuration
- `engine.conf` — Static constants: paths, host/port, engine/command whitelists, health-check patterns, SSH remote settings, exit codes
- `engine-models.json` — Model registry with per-engine metadata; loader strategies: `native | gguf | auto`

### Engine Directories (`ollama/`, `llama/`, `vllm/`)
Each engine directory contains a consistent set of scripts:
- `start.sh` — Start the engine (optionally load a model)
- `stop.sh` — Stop the engine
- `status.sh` — Check running state and model list
- `load.sh` — Load / switch a model
- `show.sh` — Show current model info
- `remove.sh` — Remove a model (where supported)
- `<engine>-api.sh` — Low-level REST API wrapper for the engine

## Model Registry (`engine-models.json`)
- GGUF format is preferred; Ollama can also pull from its registry (`native` strategy)
- `auto` loader = use GGUF if the file exists locally, fall back to native pull
- Multimodal: `mmproj` file supported for llama.cpp and ollama
- Speculative decoding: `draft_model` supported for llama.cpp

## Output Contract
- All scripts return **JSON on stdout**; debug/log output goes to **stderr**
- Consistent schema: `{ "timestamp", "status", "action", "engine", "data": {...} }`
- Standardised exit codes defined in `engine.conf`

## Known Issues / Future Work
- SSH security sandbox (ForceCommand, dedicated user, input validation) — documented in `TODO.md`, not yet implemented
- vLLM engine — stub only, not yet implemented
- Race conditions in startup health checks (fixed sleep, no retry loop) — to be addressed
- GPU reporting: engine-agnostic by design; hardware probing only as fallback

## Goal
- Complete rewrite of the system with simplification and improvements