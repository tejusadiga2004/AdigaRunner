// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import Foundation
import Vapor

private actor LoggingBootstrapState {
    static let shared = LoggingBootstrapState()

    private var hasBootstrapped = false

    func bootstrapIfNeeded(environment: inout Environment) throws {
        guard !hasBootstrapped else {
            return
        }

        try LoggingSystem.bootstrap(from: &environment)
        hasBootstrapped = true
    }
}

func makeServer(config: AppConfig, modelRunner: any LLMRunner) async throws -> Application {
    var env = Environment(name: "adiga", arguments: ["vapor"])
    try await bootstrapLoggingIfNeeded(environment: &env)

    let app = try await Application.make(env)
    app.http.server.configuration.hostname = config.host
    app.http.server.configuration.port = config.port

    let modelService = ModelService(
        runner: modelRunner,
        defaultMaxTokens: config.defaultMaxTokens,
        defaultTemperature: config.defaultTemperature
    )

    app.get("health") { _ in
        HealthResponse(status: "ok")
    }

    app.get("ready") { _ async in
        ReadyResponse(ready: modelService.isReady(), modelPath: modelService.modelPath())
    }

    app.post("v1", "generate") { req async throws -> GenerateResponse in
        let request = try req.content.decode(GenerateRequest.self)
        let started = Date()
        let output = try modelService.generate(from: request)
        let latency = Int(Date().timeIntervalSince(started) * 1000)

        return GenerateResponse(
            output: output,
            modelPath: modelService.modelPath(),
            latencyMs: latency
        )
    }

    app.post("v1", "generate", "stream") { req async throws -> Response in
        let request = try req.content.decode(GenerateRequest.self)
        let output = try modelService.generate(from: request)

        let tokens = output.split(separator: " ")
        let payload = tokens.map { "event: token\ndata: \($0)\n\n" }.joined()
            + "event: done\ndata: [DONE]\n\n"

        let headers = HTTPHeaders([
            ("Content-Type", "text/event-stream"),
            ("Cache-Control", "no-cache"),
            ("Connection", "keep-alive")
        ])

        return Response(status: .ok, headers: headers, body: .init(string: payload))
    }

    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    return app
}

private func bootstrapLoggingIfNeeded(environment: inout Environment) async throws {
    try await LoggingBootstrapState.shared.bootstrapIfNeeded(environment: &environment)
}
