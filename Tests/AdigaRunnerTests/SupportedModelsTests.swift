import XCTest
@testable import AdigaRunner

final class SupportedModelsTests: XCTestCase {
    func testModelLookupIsCaseInsensitive() {
        let model = SupportedModelCatalog.model(named: "LLAMA-3.2-1B")

        XCTAssertEqual(model?.name, "llama-3.2-1b")
    }

    func testFormattedDownloadedListReportsEmptyDirectory() throws {
        let baseDirectory = try makeTemporaryDirectory()

        let output = SupportedModelCatalog.formattedDownloadedList(from: baseDirectory)

        XCTAssertEqual(output, "No downloaded supported models found in \(baseDirectory.path)")
    }

    func testFormattedDownloadedListIncludesDownloadedModelDetails() throws {
        let baseDirectory = try makeTemporaryDirectory()
        let model = SupportedModelCatalog.all[0]
        let localPath = ModelStorage.localPath(for: model, baseDirectory: baseDirectory)
        try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true)

        let output = SupportedModelCatalog.formattedDownloadedList(from: baseDirectory)

        XCTAssertTrue(output.contains("Downloaded models:"))
        XCTAssertTrue(output.contains(model.name))
        XCTAssertTrue(output.contains(model.repoID))
        XCTAssertTrue(output.contains(localPath.path))
    }
}
