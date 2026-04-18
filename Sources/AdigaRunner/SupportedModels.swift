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
        )
    ]

    static func model(named name: String) -> SupportedModel? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func formattedList(defaultBaseDirectory: URL) -> String {
        let lines = all.map { model in
            let localPath = ModelStorage.localPath(for: model, baseDirectory: defaultBaseDirectory).path
            return "- \(model.name): \(model.description)\n  repo: \(model.repoID)\n  local path: \(localPath)"
        }

        return (["Supported models:"] + lines).joined(separator: "\n")
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
}