import Foundation
@testable import AdigaRunner

final class MockLLMRunner: LLMRunner, @unchecked Sendable {
    var ready: Bool
    var selectedModelPath: String
    var generatedOutput: String
    var generationError: Error?
    private(set) var validateEnvironmentCallCount = 0
    private(set) var loadModelCallCount = 0
    private(set) var generateCalls: [(prompt: String, maxTokens: Int, temperature: Double)] = []

    init(
        ready: Bool = true,
        selectedModelPath: String = "/tmp/mock-model",
        generatedOutput: String = "mock output",
        generationError: Error? = nil
    ) {
        self.ready = ready
        self.selectedModelPath = selectedModelPath
        self.generatedOutput = generatedOutput
        self.generationError = generationError
    }

    func validateEnvironment() throws {
        validateEnvironmentCallCount += 1
    }

    func loadModel() throws {
        loadModelCallCount += 1
        ready = true
    }

    func generate(prompt: String, maxTokens: Int, temperature: Double) throws -> String {
        generateCalls.append((prompt: prompt, maxTokens: maxTokens, temperature: temperature))

        if let generationError {
            throw generationError
        }

        return generatedOutput
    }
}

enum TestError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        switch self {
        case .expectedFailure:
            return "expected failure"
        }
    }
}

func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AdigaRunnerTests-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
