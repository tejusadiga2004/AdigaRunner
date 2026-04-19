// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import Foundation

struct SupportedModel {
    let name: String
    let repoID: String
    let localDirectoryName: String
    let description: String
}

enum SupportedModelCatalog {
    static let all: [SupportedModel] = [
        SupportedModel(
            name: "llama-3.2-1b",
            repoID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            localDirectoryName: "llama-3.2-1b",
            description: "Small general-purpose instruction model"
        ),
        SupportedModel(
            name: "llama-3.2-3b",
            repoID: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            localDirectoryName: "llama-3.2-3b",
            description: "Balanced quality and local performance"
        ),
        SupportedModel(
            name: "qwen2.5-1.5b",
            repoID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            localDirectoryName: "qwen2.5-1.5b",
            description: "Compact multilingual instruction model"
        ),
        SupportedModel(
            name: "phi-3.5-mini",
            repoID: "mlx-community/Phi-3.5-mini-instruct-4bit",
            localDirectoryName: "phi-3.5-mini",
            description: "Small reasoning-focused instruction model"
        ),
        SupportedModel(
            name: "mistral-7b",
            repoID: "mlx-community/Mistral-7B-Instruct-v0.2-4bit",
            localDirectoryName: "mistral-7b",
            description: "7B general-purpose instruction model with strong performance"
        ),
        SupportedModel(
            name: "neural-chat-7b",
            repoID: "mlx-community/neural-chat-7b-v3-2-4bit",
            localDirectoryName: "neural-chat-7b",
            description: "Intel neural-chat optimized 7B model"
        ),
        SupportedModel(
            name: "zephyr-7b",
            repoID: "mlx-community/zephyr-7b-beta-4bit",
            localDirectoryName: "zephyr-7b",
            description: "High-quality instruction-tuned Mistral variant"
        ),
        SupportedModel(
            name: "orca-mini-3b",
            repoID: "mlx-community/Orca-mini-3b-gguf-4bit",
            localDirectoryName: "orca-mini-3b",
            description: "3B reasoning-focused model"
        ),
        SupportedModel(
            name: "tinyllama-1.1b",
            repoID: "mlx-community/TinyLlama-1.1B-Chat-v1.0-4bit",
            localDirectoryName: "tinyllama-1.1b",
            description: "Extremely lightweight 1.1B model"
        ),
        SupportedModel(
            name: "gemma-2b",
            repoID: "mlx-community/Gemma-2B-4bit",
            localDirectoryName: "gemma-2b",
            description: "Google ultra-lightweight 2B model"
        ),
        SupportedModel(
            name: "stablelm-3b",
            repoID: "mlx-community/stable-zephyr-3b-4bit",
            localDirectoryName: "stablelm-3b",
            description: "Stability AI's small 3B model"
        ),
        SupportedModel(
            name: "deepseek-coder-1.3b",
            repoID: "mlx-community/deepseek-coder-1.3b-instruct-4bit",
            localDirectoryName: "deepseek-coder-1.3b",
            description: "Code generation specialist 1.3B model"
        ),
        SupportedModel(
            name: "starling-lm-7b",
            repoID: "mlx-community/Starling-LM-7B-beta-4bit",
            localDirectoryName: "starling-lm-7b",
            description: "High-quality reasoning and conversation model"
        ),
        SupportedModel(
            name: "nous-hermes-2-7b",
            repoID: "mlx-community/Nous-Hermes-2-7B-DPO-4bit",
            localDirectoryName: "nous-hermes-2-7b",
            description: "Strong reasoning and instruction-following 7B model"
        )
    ]

    static func model(named name: String) -> SupportedModel? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func formattedList(defaultBaseDirectory: URL) -> String {
        let separator = String(repeating: "═", count: 80)
        var output = "\(separator)\n"
        output += "  SUPPORTED MODELS (\(all.count) total)\n"
        output += "\(separator)\n\n"

        for (index, model) in all.enumerated() {
            let number = String(format: "%2d", index + 1)
            let localPath = ModelStorage.localPath(for: model, baseDirectory: defaultBaseDirectory).path
                .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")

            output += "[\(number)] \(model.name)\n"
            output += "        \(model.description)\n"
            output += "        Repo: \(model.repoID)\n"
            output += "        Path: \(localPath)\n"

            if index < all.count - 1 {
                output += "\n"
            }
        }

        output += "\n\(separator)\n"
        output += "Use 'adiga download-model <name>' to download a model.\n"
        output += "Use 'adiga serve <name>' to start the server with a model.\n"

        return output
    }

    static func formattedDownloadedList(from baseDirectory: URL) -> String {
        let downloadedModels = all.filter { model in
            ModelStorage.isDownloaded(model: model, baseDirectory: baseDirectory)
        }

        guard !downloadedModels.isEmpty else {
            return "No downloaded supported models found in \(baseDirectory.path)"
        }

        let lines = downloadedModels.map { model in
            let localPath = ModelStorage.localPath(for: model, baseDirectory: baseDirectory).path
            return "- \(model.name): \(model.description)\n  repo: \(model.repoID)\n  local path: \(localPath)"
        }

        return (["Downloaded models:"] + lines).joined(separator: "\n")
    }
}

enum ModelStorage {
    static func defaultBaseDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".adigarunner", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    static func localPath(for model: SupportedModel, baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(model.localDirectoryName, isDirectory: true)
    }

    static func isDownloaded(model: SupportedModel, baseDirectory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = localPath(for: model, baseDirectory: baseDirectory).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}