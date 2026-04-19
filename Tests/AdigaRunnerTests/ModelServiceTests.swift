import Vapor
import XCTest
@testable import AdigaRunner

final class ModelServiceTests: XCTestCase {
    func testGenerateTrimsPromptAndAppliesDefaultValues() throws {
        let runner = MockLLMRunner(generatedOutput: "trimmed result")
        let service = ModelService(runner: runner, defaultMaxTokens: 256, defaultTemperature: 0.7)

        let output = try service.generate(from: GenerateRequest(prompt: "  hello world  ", maxTokens: nil, temperature: nil))

        XCTAssertEqual(output, "trimmed result")
        XCTAssertEqual(runner.generateCalls.count, 1)
        XCTAssertEqual(runner.generateCalls[0].prompt, "hello world")
        XCTAssertEqual(runner.generateCalls[0].maxTokens, 256)
        XCTAssertEqual(runner.generateCalls[0].temperature, 0.7)
    }

    func testGenerateRejectsEmptyPrompt() {
        let service = ModelService(runner: MockLLMRunner(), defaultMaxTokens: 256, defaultTemperature: 0.7)

        XCTAssertThrowsError(
            try service.generate(from: GenerateRequest(prompt: "   ", maxTokens: nil, temperature: nil))
        ) { error in
            guard let abort = error as? Abort else {
                return XCTFail("Expected Abort error, got: \(error)")
            }

            XCTAssertEqual(abort.status, .badRequest)
            XCTAssertEqual(abort.reason, "prompt cannot be empty")
        }
    }

    func testGenerateRejectsInvalidMaxTokens() {
        let service = ModelService(runner: MockLLMRunner(), defaultMaxTokens: 256, defaultTemperature: 0.7)

        XCTAssertThrowsError(
            try service.generate(from: GenerateRequest(prompt: "hello", maxTokens: 0, temperature: nil))
        ) { error in
            guard let abort = error as? Abort else {
                return XCTFail("Expected Abort error, got: \(error)")
            }

            XCTAssertEqual(abort.status, .badRequest)
            XCTAssertEqual(abort.reason, "maxTokens must be between 1 and 8192")
        }
    }

    func testGenerateRejectsInvalidTemperature() {
        let service = ModelService(runner: MockLLMRunner(), defaultMaxTokens: 256, defaultTemperature: 0.7)

        XCTAssertThrowsError(
            try service.generate(from: GenerateRequest(prompt: "hello", maxTokens: nil, temperature: 2.5))
        ) { error in
            guard let abort = error as? Abort else {
                return XCTFail("Expected Abort error, got: \(error)")
            }

            XCTAssertEqual(abort.status, .badRequest)
            XCTAssertEqual(abort.reason, "temperature must be between 0.0 and 2.0")
        }
    }

    func testGenerateWrapsRunnerFailuresAsInternalServerError() {
        let runner = MockLLMRunner(generationError: TestError.expectedFailure)
        let service = ModelService(runner: runner, defaultMaxTokens: 256, defaultTemperature: 0.7)

        XCTAssertThrowsError(
            try service.generate(from: GenerateRequest(prompt: "hello", maxTokens: nil, temperature: nil))
        ) { error in
            guard let abort = error as? Abort else {
                return XCTFail("Expected Abort error, got: \(error)")
            }

            XCTAssertEqual(abort.status, .internalServerError)
            XCTAssertEqual(abort.reason, "expected failure")
        }
    }
}
