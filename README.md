# AdigaRunner

A local macOS CLI app written in Swift that runs an LLM via MLX and exposes HTTP endpoints.

See DESIGN.md for requirements, architecture, and low-level design details.

## What It Does

- Starts a local HTTP server.
- Loads the model specified in CLI arguments.
- Accepts prompts through REST endpoints.
- Returns generated output to the caller.

## Prerequisites

- macOS 13+
- Xcode command line tools / Swift toolchain
- Python 3
- `mlx-lm` Python package:

```bash
pip install mlx-lm
```

## Build

```bash
swift build
```

To create a release binary in `dist/adiga`:

```bash
./scripts/build_binary.sh
```

To write the binary to a custom output directory:

```bash
./scripts/build_binary.sh /path/to/output
```

## Run

```bash
swift run adiga <model_path> --host 127.0.0.1 --port 8080 --max-tokens 256 --temperature 0.7
```

You can also use a supported model name instead of a direct path after downloading it locally:

```bash
swift run adiga llama-3.2-1b
```

## Supported Models

List the hard-coded supported models:

```bash
swift run adiga list-models
```

List only the supported models that are already downloaded locally:

```bash
swift run adiga list-available-models
```

Download one of the supported models to the default local storage directory:

```bash
swift run adiga download-model llama-3.2-1b
```

The downloader prints file-by-file progress updates while the model is being fetched.
If a download is interrupted, partially downloaded files are kept as resumable `.part` files and the next download attempt resumes automatically when the server supports range requests.

Use a custom local model storage directory:

```bash
swift run adiga list-available-models --models-dir ./models
swift run adiga download-model llama-3.2-1b --models-dir ./models
swift run adiga serve llama-3.2-1b --models-dir ./models
```

## Endpoints

- `GET /health`
- `GET /ready`
- `POST /v1/generate`
- `POST /v1/generate/stream`

### Generate Request

```json
{
  "prompt": "Write a haiku about macOS",
  "maxTokens": 128,
  "temperature": 0.7
}
```

### Generate Response

```json
{
  "output": "...",
  "modelPath": "/path/to/model",
  "latencyMs": 1234
}
```

### Streaming Response

`/v1/generate/stream` returns `text/event-stream` with events:

- `event: token`
- `event: done`

## Notes

- Current implementation uses a Swift model runner that invokes `python3 -m mlx_lm.generate` under the hood.
- This keeps the app fully Swift for server and CLI while running inference through MLX.
- Supported model downloads use native Swift HTTP requests against Hugging Face.
- Supported model downloads are stored under `~/.adigarunner/models` by default.
