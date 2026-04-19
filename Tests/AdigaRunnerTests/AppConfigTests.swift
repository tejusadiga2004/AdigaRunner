import XCTest
@testable import AdigaRunner

final class AppConfigTests: XCTestCase {
    func testListModelsParsesCustomModelsDirectory() throws {
        let customDirectory = URL(fileURLWithPath: "/tmp/adiga-models", isDirectory: true)

        let command = try AppConfig.parseCommand(
            from: ["adiga", "list-models", "--models-dir", customDirectory.path]
        )

        guard case .listModels(let modelsDirectory) = command else {
            return XCTFail("Expected list-models command")
        }

        XCTAssertEqual(modelsDirectory.path, customDirectory.path)
    }

    func testDownloadModelParsesSupportedModelAndCustomDirectory() throws {
        let customDirectory = URL(fileURLWithPath: "/tmp/download-models", isDirectory: true)

        let command = try AppConfig.parseCommand(
            from: ["adiga", "download-model", "llama-3.2-1b", "--models-dir", customDirectory.path]
        )

        guard case .downloadModel(let config) = command else {
            return XCTFail("Expected download-model command")
        }

        XCTAssertEqual(config.model.name, "llama-3.2-1b")
        XCTAssertEqual(config.modelsDirectory.path, customDirectory.path)
    }

    func testServeParsesDirectModelPathAndOverrides() throws {
        let modelPath = "/models/custom-model"
        let modelsDirectory = URL(fileURLWithPath: "/tmp/unused", isDirectory: true)

        let command = try AppConfig.parseCommand(
            from: [
                "adiga",
                modelPath,
                "--host", "0.0.0.0",
                "--port", "9000",
                "--max-tokens", "512",
                "--temperature", "0.2",
                "--models-dir", modelsDirectory.path
            ]
        )

        guard case .serve(let config) = command else {
            return XCTFail("Expected serve command")
        }

        XCTAssertEqual(config.modelReference, modelPath)
        XCTAssertEqual(config.modelPath, modelPath)
        XCTAssertEqual(config.host, "0.0.0.0")
        XCTAssertEqual(config.port, 9000)
        XCTAssertEqual(config.defaultMaxTokens, 512)
        XCTAssertEqual(config.defaultTemperature, 0.2)
        XCTAssertEqual(config.modelsDirectory.path, modelsDirectory.path)
    }

    func testServeResolvesDownloadedSupportedModelFromCustomDirectory() throws {
        let baseDirectory = try makeTemporaryDirectory()
        let localModelPath = ModelStorage.localPath(
            for: SupportedModelCatalog.all[0],
            baseDirectory: baseDirectory
        )
        try FileManager.default.createDirectory(at: localModelPath, withIntermediateDirectories: true)

        let command = try AppConfig.parseCommand(
            from: ["adiga", "serve", "llama-3.2-1b", "--models-dir", baseDirectory.path]
        )

        guard case .serve(let config) = command else {
            return XCTFail("Expected serve command")
        }

        XCTAssertEqual(config.modelReference, "llama-3.2-1b")
        XCTAssertEqual(config.modelPath, localModelPath.path)
        XCTAssertEqual(config.modelsDirectory.path, baseDirectory.path)
    }

    func testServeThrowsWhenSupportedModelIsNotDownloaded() {
        let baseDirectory = try! makeTemporaryDirectory()

        XCTAssertThrowsError(
            try AppConfig.parseCommand(from: ["adiga", "serve", "llama-3.2-1b", "--models-dir", baseDirectory.path])
        ) { error in
            guard case ConfigError.modelNotDownloaded(let name, let path) = error else {
                return XCTFail("Expected modelNotDownloaded error, got: \(error)")
            }

            XCTAssertEqual(name, "llama-3.2-1b")
            XCTAssertTrue(path.hasSuffix("llama-3.2-1b"))
        }
    }

    func testServeThrowsForInvalidPort() {
        XCTAssertThrowsError(
            try AppConfig.parseCommand(from: ["adiga", "/tmp/model", "--port", "70000"])
        ) { error in
            guard case ConfigError.invalidValue(let flag, let value) = error else {
                return XCTFail("Expected invalidValue error, got: \(error)")
            }

            XCTAssertEqual(flag, "--port")
            XCTAssertEqual(value, "70000")
        }
    }
}
