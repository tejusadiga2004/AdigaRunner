// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import Foundation
import Vapor

struct GenerateRequest: Content {
    let prompt: String
    let maxTokens: Int?
    let temperature: Double?
}

struct GenerateResponse: Content {
    let output: String
    let modelPath: String
    let latencyMs: Int
}

struct HealthResponse: Content {
    let status: String
}

struct ReadyResponse: Content {
    let ready: Bool
    let modelPath: String
}

struct ErrorResponse: Content {
    let error: String
}
