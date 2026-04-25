# Copilot Instructions

## Build and Test

```bash
# Build (debug)
swift build

# Run tests
swift test

# Run a single test class
swift test --filter AdigaRunnerTests.HTTPServerTests
swift test --filter AdigaRunnerTests.AppConfigTests
swift test --filter AdigaRunnerTests.ModelServiceTests
swift test --filter AdigaRunnerTests.SupportedModelsTests

# Release binary → dist/adiga
./scripts/build_binary.sh
```

Requirements: macOS 15+, Swift 6.1, `python3` with `mlx-lm` installed (`pip install mlx-lm`).

## Architecture

AdigaRunner is a Swift 6.1 macOS CLI that exposes a local HTTP API for LLM inference. It uses **Vapor 4** for the HTTP server and delegates all inference to a `python3 -m mlx_lm generate` subprocess.

### Component Map

| File | Responsibility |
|---|---|
| `AdigaRunner.swift` | `@main` entry — dispatches `CLICommand` cases |
| `AppConfig.swift` | Manual CLI argument parsing; produces `CLICommand`, `AppConfig`, `DownloadConfig` |
| `SupportedModels.swift` | Hard-coded `SupportedModelCatalog` (14 models) + `ModelStorage` path resolution |
| `ModelDownloader.swift` | Native Swift HTTP downloader from Hugging Face; resumable via `.part` files |
| `HTTPServer.swift` | `makeServer()` free function — creates and configures the Vapor `Application` |
| `ModelService.swift` | Validates generate requests, applies defaults, serializes inference with `NSLock` |
| `MLXModelRunner.swift` | `LLMRunner` protocol + production `MLXModelRunner` + `RunnerError` enum |
| `APIModels.swift` | Vapor `Content` structs: `GenerateRequest`, `GenerateResponse`, `HealthResponse`, `ReadyResponse` |

Tests share `TestSupport.swift` which provides `MockLLMRunner` and `makeTemporaryDirectory()`.

### Request Flow

```
HTTP POST /v1/generate
  → Vapor route in makeServer()
  → ModelService.generate(from:)   ← validates prompt, maxTokens, temperature
  → LLMRunner.generate(...)        ← MLXModelRunner spawns python3 subprocess
```

### Inference Backend

`MLXModelRunner` runs `python3 -m mlx_lm generate --model <path> --prompt <text> --max-tokens <n> --temp <t>` as a subprocess and parses stdout. Startup warms the model with a single one-token generation before the server reports `/ready`.

The `/v1/generate/stream` endpoint is **simulated**: it generates the full output first, then splits on spaces and emits SSE `event: token` events — it is not true token-by-token streaming.

## Key Conventions

### CLI Parsing
There is no `ArgumentParser` dependency. Parsing is done manually in `AppConfig.parseCommand(from:)` with a `while index < args.count` loop. If the first argument is not a recognized subcommand (`list-models`, `list-available-models`, `download-model`, `serve`), it is treated as a model reference and `serve` is implied.

### LLMRunner Protocol and Testability
`LLMRunner` is the interface for inference backends. `makeServer()` accepts `any LLMRunner`, enabling full HTTP integration tests using `MockLLMRunner` from `TestSupport.swift` without needing a real model or Python. Tests use `@testable import AdigaRunner`.

### Error Handling
All user-facing errors are `LocalizedError` enums (`ConfigError`, `RunnerError`) with a `var errorDescription: String?` switch. The `@main` entry prints `error.localizedDescription` to stderr and exits with code 2 on CLI errors, 1 on startup failures.

### Model Storage
Supported models resolve to `~/.adigarunner/models/<localDirectoryName>` by default. A `--models-dir` flag overrides this on every command. Model name lookup is case-insensitive (`caseInsensitiveCompare`).

### Concurrency
`ModelService` is `final class: @unchecked Sendable` and uses `NSLock` to serialize inference calls. `LoggingBootstrapState` in `HTTPServer.swift` is an `actor` to guard one-time Vapor logging bootstrap.
