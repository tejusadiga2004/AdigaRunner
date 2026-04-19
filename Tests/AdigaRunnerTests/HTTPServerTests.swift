import XCTVapor
import XCTest
@testable import AdigaRunner

final class HTTPServerTests: XCTestCase {
    func testHealthEndpointReturnsOk() async throws {
        try await withTestApplication { _, tester in
            try await tester.test(.GET, "health", afterResponse: { response async throws in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(try response.content.decode(HealthResponse.self).status, "ok")
            })
        }
    }

    func testReadyEndpointReturnsRunnerState() async throws {
        let runner = MockLLMRunner(ready: false, selectedModelPath: "/tmp/not-ready-model")
        try await withTestApplication(runner: runner) { _, tester in
            try await tester.test(.GET, "ready", afterResponse: { response async throws in
                let ready = try response.content.decode(ReadyResponse.self)
                XCTAssertEqual(response.status, .ok)
                XCTAssertFalse(ready.ready)
                XCTAssertEqual(ready.modelPath, "/tmp/not-ready-model")
            })
        }
    }

    func testGenerateEndpointReturnsOutputAndUsesDefaults() async throws {
        let runner = MockLLMRunner(generatedOutput: "server output")
        try await withTestApplication(runner: runner) { _, tester in
            try await tester.test(.POST, "v1/generate", beforeRequest: { request async throws in
                try request.content.encode(GenerateRequest(prompt: "hello", maxTokens: nil, temperature: nil))
            }, afterResponse: { response async throws in
                let payload = try response.content.decode(GenerateResponse.self)

                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(payload.output, "server output")
                XCTAssertEqual(payload.modelPath, "/tmp/mock-model")
                XCTAssertGreaterThanOrEqual(payload.latencyMs, 0)
            })
        }

        XCTAssertEqual(runner.generateCalls.count, 1)
        XCTAssertEqual(runner.generateCalls[0].prompt, "hello")
        XCTAssertEqual(runner.generateCalls[0].maxTokens, 256)
        XCTAssertEqual(runner.generateCalls[0].temperature, 0.7)
    }

    func testGenerateEndpointReturnsBadRequestForInvalidPrompt() async throws {
        try await withTestApplication { _, tester in
            try await tester.test(.POST, "v1/generate", beforeRequest: { request async throws in
                try request.content.encode(GenerateRequest(prompt: "   ", maxTokens: nil, temperature: nil))
            }, afterResponse: { response async throws in
                XCTAssertEqual(response.status, .badRequest)
                XCTAssertTrue(response.body.string.contains("prompt cannot be empty"))
            })
        }
    }

    func testStreamEndpointReturnsServerSentEventPayload() async throws {
        let runner = MockLLMRunner(generatedOutput: "alpha beta")
        try await withTestApplication(runner: runner) { _, tester in
            try await tester.test(.POST, "v1/generate/stream", beforeRequest: { request async throws in
                try request.content.encode(GenerateRequest(prompt: "stream", maxTokens: 4, temperature: 0.1))
            }, afterResponse: { response async throws in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers.first(name: .contentType), "text/event-stream")

                let body = response.body.string
                XCTAssertTrue(body.contains("event: token\ndata: alpha"))
                XCTAssertTrue(body.contains("event: token\ndata: beta"))
                XCTAssertTrue(body.contains("event: done\ndata: [DONE]"))
            })
        }
    }

    private func makeTestApplication(runner: MockLLMRunner = MockLLMRunner()) async throws -> Application {
        try await makeServer(
            config: AppConfig(
                modelReference: "mock-model",
                modelPath: runner.selectedModelPath,
                host: "127.0.0.1",
                port: 8080,
                defaultMaxTokens: 256,
                defaultTemperature: 0.7,
                modelsDirectory: URL(fileURLWithPath: "/tmp/models", isDirectory: true)
            ),
            modelRunner: runner
        )
    }

    private func withTestApplication(
        runner: MockLLMRunner = MockLLMRunner(),
        testBody: (Application, XCTApplicationTester) async throws -> Void
    ) async throws {
        let app = try await makeTestApplication(runner: runner)
        let tester = try app.testable()

        do {
            try await testBody(app, tester)
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }
}