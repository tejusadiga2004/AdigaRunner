// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import Foundation
import Vapor

@main
struct AdigaRunner {
    static func main() async {
        do {
            let command = try AppConfig.parseCommand(from: CommandLine.arguments)

            switch command {
            case .listModels(let modelsDirectory):
                print(SupportedModelCatalog.formattedList(defaultBaseDirectory: modelsDirectory))
            case .listDownloadedModels(let modelsDirectory):
                print(SupportedModelCatalog.formattedDownloadedList(from: modelsDirectory))
            case .downloadModel(let downloadConfig):
                let downloader = ModelDownloader()
                let localPath = try await downloader.download(downloadConfig)
                print("Downloaded \(downloadConfig.model.name) to \(localPath.path)")
            case .serve(let config):
                try await runServer(with: config)
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            Foundation.exit(2)
        }
    }

    private static func runServer(with config: AppConfig) async throws {
        let modelRunner = MLXModelRunner(modelPath: config.modelPath)

        do {
            try modelRunner.validateEnvironment()
            try modelRunner.loadModel()
        } catch {
            FileHandle.standardError.write(Data("Startup failed: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }

        let app = try await makeServer(config: config, modelRunner: modelRunner)
        defer {
            Task {
                try? await app.asyncShutdown()
            }
        }

        app.logger.notice("Server listening on http://\(config.host):\(config.port)")
        app.logger.notice("Loaded model reference: \(config.modelReference)")
        app.logger.notice("Resolved model path: \(config.modelPath)")

        try await app.execute()
    }
}
