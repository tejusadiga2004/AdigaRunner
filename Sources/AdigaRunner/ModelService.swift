// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import Foundation
import Vapor

final class ModelService: @unchecked Sendable {
    private let runner: MLXModelRunner
    private let defaultMaxTokens: Int
    private let defaultTemperature: Double
    private let lock = NSLock()

    init(runner: MLXModelRunner, defaultMaxTokens: Int, defaultTemperature: Double) {
        self.runner = runner
        self.defaultMaxTokens = defaultMaxTokens
        self.defaultTemperature = defaultTemperature
    }

    func isReady() -> Bool {
        runner.ready
    }

    func modelPath() -> String {
        runner.selectedModelPath
    }

    func generate(from request: GenerateRequest) throws -> String {
        let trimmedPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw Abort(.badRequest, reason: "prompt cannot be empty")
        }

        let maxTokens = request.maxTokens ?? defaultMaxTokens
        let temperature = request.temperature ?? defaultTemperature

        guard maxTokens > 0 && maxTokens <= 8192 else {
            throw Abort(.badRequest, reason: "maxTokens must be between 1 and 8192")
        }

        guard temperature >= 0.0 && temperature <= 2.0 else {
            throw Abort(.badRequest, reason: "temperature must be between 0.0 and 2.0")
        }

        lock.lock()
        defer { lock.unlock() }

        do {
            return try runner.generate(prompt: trimmedPrompt, maxTokens: maxTokens, temperature: temperature)
        } catch {
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }
    }
}
