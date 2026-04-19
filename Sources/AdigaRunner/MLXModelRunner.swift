// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import Foundation

protocol LLMRunner: AnyObject {
    func validateEnvironment() throws
    func loadModel() throws
    func generate(prompt: String, maxTokens: Int, temperature: Double) throws -> String
    var ready: Bool { get }
    var selectedModelPath: String { get }
}

final class MLXModelRunner: LLMRunner {
    private let modelPath: String
    private var isLoaded = false

    init(modelPath: String) {
        self.modelPath = modelPath
    }

    func validateEnvironment() throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDirectory)
        guard exists else {
            throw RunnerError.modelNotFound(modelPath)
        }

        guard FileManager.default.isReadableFile(atPath: modelPath) else {
            throw RunnerError.modelNotReadable(modelPath)
        }

        let pythonCheck = Process()
        pythonCheck.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        pythonCheck.arguments = ["python3", "-c", "import mlx_lm"]

        do {
            try pythonCheck.run()
            pythonCheck.waitUntilExit()
        } catch {
            throw RunnerError.pythonUnavailable
        }

        guard pythonCheck.terminationStatus == 0 else {
            throw RunnerError.mlxUnavailable
        }
    }

    func loadModel() throws {
        // Warmup one-token generation so first request does not pay all lazy initialization.
        _ = try generate(prompt: "hello", maxTokens: 1, temperature: 0.0)
        isLoaded = true
    }

    func generate(prompt: String, maxTokens: Int, temperature: Double) throws -> String {
        let startedAt = Date()
        log("Inference started. promptChars=\(prompt.count) maxTokens=\(maxTokens) temperature=\(temperature)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-m", "mlx_lm", "generate",
            "--model", modelPath,
            "--prompt", prompt,
            "--max-tokens", String(maxTokens),
            "--temp", String(temperature)
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        guard process.terminationStatus == 0 else {
            let compactError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            log("Inference failed. status=\(process.terminationStatus) durationMs=\(elapsedMs) stderrChars=\(compactError.count)")
            throw RunnerError.inferenceFailed(stderr.isEmpty ? "Unknown inference failure." : stderr)
        }

        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log("Inference returned empty output. durationMs=\(elapsedMs)")
            throw RunnerError.emptyOutput
        }

        log("Inference completed. durationMs=\(elapsedMs) outputChars=\(trimmed.count)")

        return trimmed
    }

    private func log(_ message: String) {
        let timestamp = Date().ISO8601Format()
        let line = "[MLXModelRunner] \(timestamp) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    var ready: Bool { isLoaded }
    var selectedModelPath: String { modelPath }
}

enum RunnerError: LocalizedError {
    case modelNotFound(String)
    case modelNotReadable(String)
    case pythonUnavailable
    case mlxUnavailable
    case inferenceFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model path does not exist: \(path)"
        case .modelNotReadable(let path):
            return "Model path is not readable: \(path)"
        case .pythonUnavailable:
            return "python3 is unavailable. Install Python 3."
        case .mlxUnavailable:
            return "mlx_lm is unavailable. Install with: pip install mlx-lm"
        case .inferenceFailed(let details):
            return "Inference failed: \(details)"
        case .emptyOutput:
            return "Inference produced empty output."
        }
    }
}
