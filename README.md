# AdigaRunner

AdigaRunner is a local macOS CLI application written in Swift that exposes a simple HTTP API for local LLM inference.

It supports two ways to run a model:

- start the server with a direct local model path
- download and serve one of the built-in supported models

The current implementation keeps the CLI, downloader, and HTTP server in Swift, and runs inference by invoking `python3 -m mlx_lm generate` under the hood.

See `DESIGN.md` for architecture and design notes.

## Features

- Local HTTP server for prompt-based generation
- Health and readiness endpoints
- Built-in catalog of supported MLX model repositories
- Native Swift downloader for supported models from Hugging Face
- Resumable downloads using `.part` files when range requests are supported
- Configurable host, port, max tokens, and temperature

## Requirements

- macOS 15+
- Swift 6.1 toolchain / Xcode command line tools
- Python 3 available as `python3`
- `mlx-lm` installed in that Python environment

Install the Python dependency:

```bash
pip install mlx-lm
```

## Build

Build the package:

```bash
swift build
```

Create a release binary in `dist/adiga`:

```bash
./scripts/build_binary.sh
```

Write the release binary to a custom output directory:

```bash
./scripts/build_binary.sh /path/to/output
```

## CLI Overview

```text
adiga list-models [--models-dir <path>]
adiga list-available-models [--models-dir <path>]
adiga download-model <name> [--models-dir <path>]
adiga serve <model-name|model-path> [--host 127.0.0.1] [--port 8080] [--max-tokens 256] [--temperature 0.7] [--models-dir <path>]
adiga <model-name|model-path> [--host 127.0.0.1] [--port 8080] [--max-tokens 256] [--temperature 0.7] [--models-dir <path>]
```

`serve` is optional. If the first argument is not a known subcommand, AdigaRunner treats it as the model reference and starts the server.

## Quick Start

Start the server with a direct local model path:

```bash
swift run adiga /path/to/local/model
```

Start the server with a downloaded supported model:

```bash
swift run adiga serve llama-3.2-1b
```

Override server defaults:

```bash
swift run adiga serve llama-3.2-1b \
  --host 127.0.0.1 \
  --port 8080 \
  --max-tokens 512 \
  --temperature 0.4
```

## Supported Models

The built-in catalog currently includes:

- `llama-3.2-1b` - Small general-purpose instruction model
- `llama-3.2-3b` - Balanced quality and local performance
- `qwen2.5-1.5b` - Compact multilingual instruction model
- `phi-3.5-mini` - Small reasoning-focused instruction model

List all supported models:

```bash
swift run adiga list-models
```

List only supported models already present on disk:

```bash
swift run adiga list-available-models
```

Download a supported model into the default storage location:

```bash
swift run adiga download-model llama-3.2-1b
```

By default, supported models are stored under:

```text
~/.adigarunner/models
```

Use a custom storage directory:

```bash
swift run adiga list-available-models --models-dir ./models
swift run adiga download-model llama-3.2-1b --models-dir ./models
swift run adiga serve llama-3.2-1b --models-dir ./models
```

The downloader prints per-file progress, skips files already present, and resumes partial downloads from `.part` files when the remote server supports range requests.

## HTTP API

Default server address:

```text
http://127.0.0.1:8080
```

### Endpoints

- `GET /health`
- `GET /ready`
- `POST /v1/generate`
- `POST /v1/generate/stream`

### Health Check

```bash
curl http://127.0.0.1:8080/health
```

Response:

```json
{
  "status": "ok"
}
```

### Readiness Check

```bash
curl http://127.0.0.1:8080/ready
```

Response:

```json
{
  "ready": true,
  "modelPath": "/path/to/model"
}
```

### Generate

Request:

```bash
curl -X POST http://127.0.0.1:8080/v1/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "Write a haiku about macOS.",
    "maxTokens": 128,
    "temperature": 0.7
  }'
```

Request body:

```json
{
  "prompt": "Write a haiku about macOS.",
  "maxTokens": 128,
  "temperature": 0.7
}
```

- `prompt` is required and must not be empty after trimming whitespace
- `maxTokens` is optional; defaults to the CLI `--max-tokens` value
- `temperature` is optional; defaults to the CLI `--temperature` value
- valid `maxTokens` range: `1...8192`
- valid `temperature` range: `0.0...2.0`

Response:

```json
{
  "output": "...",
  "modelPath": "/path/to/model",
  "latencyMs": 1234
}
```

### Streaming

Request:

```bash
curl -N -X POST http://127.0.0.1:8080/v1/generate/stream \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "List three uses for a local LLM.",
    "maxTokens": 64,
    "temperature": 0.3
  }'
```

Response content type:

```text
text/event-stream
```

Events:

- `event: token`
- `event: done`

Current behavior: the implementation first generates the full output, then splits it on spaces and returns those chunks as SSE token events. It is not true token-by-token live decoding from the model process.

## Runtime Notes

- Startup validates that the model path exists and is readable.
- Startup also checks that `python3` can import `mlx_lm`.
- The model is warmed with a one-token generation before the server reports ready.
- Request handling is serialized with a lock inside `ModelService`.

## Errors

Common failures include:

- missing or unreadable model path
- unsupported model name for `download-model`
- supported model selected before it has been downloaded
- invalid `maxTokens` or `temperature` values
- empty prompts
- Python or `mlx-lm` not installed
