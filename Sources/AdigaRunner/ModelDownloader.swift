import Foundation

final class ModelDownloader {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(_ config: DownloadConfig) async throws -> URL {
        let tree = try await fetchRepositoryTree(repoID: config.model.repoID)
        let files = tree
            .filter { $0.type == "file" }
            .sorted { $0.path < $1.path }

        guard !files.isEmpty else {
            throw DownloaderError.noFilesFound(config.model.repoID)
        }

        let targetDirectory = ModelStorage.localPath(for: config.model, baseDirectory: config.modelsDirectory)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        print("Downloading model \(config.model.name) from \(config.model.repoID)")
        print("Target directory: \(targetDirectory.path)")
        print("Files to download: \(files.count)")

        for (index, file) in files.enumerated() {
            try await downloadFile(
                repoID: config.model.repoID,
                remotePath: file.path,
                targetDirectory: targetDirectory,
                fileIndex: index + 1,
                totalFiles: files.count
            )
        }

        print("Download complete for model \(config.model.name)")

        return targetDirectory
    }

    private func fetchRepositoryTree(repoID: String) async throws -> [HuggingFaceTreeEntry] {
        let url = makeTreeURL(repoID: repoID)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AdigaRunner/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, repoID: repoID)
            return try JSONDecoder().decode([HuggingFaceTreeEntry].self, from: data)
        } catch {
            if let downloaderError = error as? DownloaderError {
                throw downloaderError
            }

            throw DownloaderError.networkFailure(error.localizedDescription)
        }
    }

    private func downloadFile(
        repoID: String,
        remotePath: String,
        targetDirectory: URL,
        fileIndex: Int,
        totalFiles: Int
    ) async throws {
        let destinationURL = targetDirectory.appending(path: remotePath)
        let partialURL = destinationURL.appendingPathExtension("part")
        let parentDirectory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            print("[\(fileIndex)/\(totalFiles)] Skipping existing file: \(remotePath)")
            return
        }

        do {
            try await performDownload(
                repoID: repoID,
                remotePath: remotePath,
                destinationURL: destinationURL,
                partialURL: partialURL,
                fileIndex: fileIndex,
                totalFiles: totalFiles,
                allowRestart: true
            )
            print("[\(fileIndex)/\(totalFiles)] Saved \(remotePath)")
        } catch {
            if let downloaderError = error as? DownloaderError {
                throw downloaderError
            }

            throw DownloaderError.downloadFailed(remotePath, error.localizedDescription)
        }
    }

    private func performDownload(
        repoID: String,
        remotePath: String,
        destinationURL: URL,
        partialURL: URL,
        fileIndex: Int,
        totalFiles: Int,
        allowRestart: Bool
    ) async throws {
        let existingBytes = partialFileSize(at: partialURL)
        var request = URLRequest(url: makeResolveURL(repoID: repoID, remotePath: remotePath))
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("AdigaRunner/1.0", forHTTPHeaderField: "User-Agent")

        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            let existingMB = String(format: "%.1f", Double(existingBytes) / 1_048_576)
            print("[\(fileIndex)/\(totalFiles)] Resuming \(remotePath) from \(existingMB) MB")
        } else {
            print("[\(fileIndex)/\(totalFiles)] Downloading \(remotePath)")
        }

        let progressDelegate = FileDownloadProgressDelegate(
            repoID: repoID,
            remotePath: remotePath,
            partialURL: partialURL,
            existingBytes: existingBytes,
            fileIndex: fileIndex,
            totalFiles: totalFiles
        )
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 0
        let downloadSession = URLSession(configuration: configuration, delegate: progressDelegate, delegateQueue: nil)

        do {
            let result = try await progressDelegate.download(with: request, session: downloadSession)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            if FileManager.default.fileExists(atPath: partialURL.path) {
                try FileManager.default.moveItem(at: partialURL, to: destinationURL)
            } else {
                throw DownloaderError.downloadFailed(remotePath, "Expected partial file was not found after download.")
            }

            if let totalBytes = result.totalBytes {
                let finalSize = partialFileSize(at: destinationURL)
                guard finalSize == totalBytes else {
                    throw DownloaderError.downloadFailed(
                        remotePath,
                        "Downloaded file size mismatch. Expected \(totalBytes) bytes, got \(finalSize) bytes."
                    )
                }
            }
        } catch ResumeDownloadError.restartRequired {
            guard allowRestart else {
                throw DownloaderError.downloadFailed(remotePath, "Server did not honor resume requests.")
            }

            if FileManager.default.fileExists(atPath: partialURL.path) {
                try FileManager.default.removeItem(at: partialURL)
            }

            print("[\(fileIndex)/\(totalFiles)] Restarting \(remotePath) from the beginning")
            try await performDownload(
                repoID: repoID,
                remotePath: remotePath,
                destinationURL: destinationURL,
                partialURL: partialURL,
                fileIndex: fileIndex,
                totalFiles: totalFiles,
                allowRestart: false
            )
        }
    }

    private func partialFileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return 0
        }

        return Int64(fileSize)
    }

    private func validate(response: URLResponse, repoID: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloaderError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401, 403:
                throw DownloaderError.accessDenied(repoID)
            case 404:
                throw DownloaderError.repositoryNotFound(repoID)
            default:
                throw DownloaderError.httpFailure(httpResponse.statusCode)
            }
        }
    }

    private func makeTreeURL(repoID: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.percentEncodedPath = "/api/models/\(encodePath(repoID))/tree/main"
        components.queryItems = [
            URLQueryItem(name: "recursive", value: "1")
        ]

        return components.url!
    }

    private func makeResolveURL(repoID: String, remotePath: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.percentEncodedPath = "/\(encodePath(repoID))/resolve/main/\(encodePath(remotePath))"
        return components.url!
    }

    private func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private struct HuggingFaceTreeEntry: Decodable {
    let path: String
    let type: String
}

private enum ResumeDownloadError: Error {
    case restartRequired
}

private struct FileDownloadResult {
    let totalBytes: Int64?
}

private final class FileDownloadProgressDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let repoID: String
    private let remotePath: String
    private let partialURL: URL
    private let existingBytes: Int64
    private let fileIndex: Int
    private let totalFiles: Int
    private var continuation: CheckedContinuation<FileDownloadResult, Error>?
    private var response: HTTPURLResponse?
    private var fileHandle: FileHandle?
    private var totalBytesExpected: Int64?
    private var didFinishSuccessfully = false
    private var lastReportedPercent = -1
    private var lastReportedBytes: Int64
    private var totalBytesWritten: Int64

    init(
        repoID: String,
        remotePath: String,
        partialURL: URL,
        existingBytes: Int64,
        fileIndex: Int,
        totalFiles: Int
    ) {
        self.repoID = repoID
        self.remotePath = remotePath
        self.partialURL = partialURL
        self.existingBytes = existingBytes
        self.fileIndex = fileIndex
        self.totalFiles = totalFiles
        self.lastReportedBytes = existingBytes
        self.totalBytesWritten = existingBytes
    }

    func download(with request: URLRequest, session: URLSession) async throws -> FileDownloadResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.dataTask(with: request)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DownloaderError.invalidResponse
            }

            try validate(httpResponse: httpResponse)
            try prepareFileHandle(for: httpResponse)
            self.response = httpResponse
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
            continuation?.resume(throwing: error)
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            totalBytesWritten += Int64(data.count)
            reportProgressIfNeeded()
        } catch {
            dataTask.cancel()
            continuation?.resume(throwing: DownloaderError.downloadFailed(remotePath, error.localizedDescription))
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            try? fileHandle?.close()
            fileHandle = nil
            continuation = nil
            session.finishTasksAndInvalidate()
        }

        if let error {
            if let urlError = error as? URLError, urlError.code == .cancelled, didFinishSuccessfully {
                return
            }

            continuation?.resume(throwing: DownloaderError.downloadFailed(remotePath, error.localizedDescription))
            return
        }

        if lastReportedPercent < 100, totalBytesExpected != nil {
            print("[\(fileIndex)/\(totalFiles)] \(remotePath) 100%")
        }

        continuation?.resume(returning: FileDownloadResult(totalBytes: totalBytesExpected))
    }

    private func validate(httpResponse: HTTPURLResponse) throws {
        switch httpResponse.statusCode {
        case 200:
            if existingBytes > 0 {
                throw ResumeDownloadError.restartRequired
            }
        case 206:
            break
        case 401, 403:
            throw DownloaderError.accessDenied(repoID)
        case 404:
            throw DownloaderError.repositoryNotFound(repoID)
        default:
            throw DownloaderError.httpFailure(httpResponse.statusCode)
        }
    }

    private func prepareFileHandle(for response: HTTPURLResponse) throws {
        let resumed = existingBytes > 0 && response.statusCode == 206

        if resumed {
            try ensurePartialFileExists()
            fileHandle = try FileHandle(forWritingTo: partialURL)
            try fileHandle?.seekToEnd()
        } else {
            if FileManager.default.fileExists(atPath: partialURL.path) {
                try FileManager.default.removeItem(at: partialURL)
            }
            FileManager.default.createFile(atPath: partialURL.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: partialURL)
            try fileHandle?.truncate(atOffset: 0)
        }

        totalBytesExpected = expectedTotalBytes(from: response, resumed: resumed)
        totalBytesWritten = resumed ? existingBytes : 0
        lastReportedBytes = totalBytesWritten
        if let totalBytesExpected {
            let initialPercent = Int((Double(totalBytesWritten) / Double(totalBytesExpected)) * 100)
            lastReportedPercent = max(lastReportedPercent, initialPercent)
        }
    }

    private func ensurePartialFileExists() throws {
        if !FileManager.default.fileExists(atPath: partialURL.path) {
            throw DownloaderError.downloadFailed(remotePath, "Partial file is missing for resume.")
        }
    }

    private func expectedTotalBytes(from response: HTTPURLResponse, resumed: Bool) -> Int64? {
        if resumed,
           let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let totalBytes = parseTotalBytes(fromContentRange: contentRange) {
            return totalBytes
        }

        let expectedLength = response.expectedContentLength
        guard expectedLength > 0 else {
            return nil
        }

        return resumed ? existingBytes + expectedLength : expectedLength
    }

    private func parseTotalBytes(fromContentRange value: String) -> Int64? {
        guard let slashIndex = value.lastIndex(of: "/") else {
            return nil
        }

        let totalPart = value[value.index(after: slashIndex)...]
        guard totalPart != "*" else {
            return nil
        }

        return Int64(totalPart)
    }

    private func reportProgressIfNeeded() {
        if let totalBytesExpected, totalBytesExpected > 0 {
            let percent = Int((Double(totalBytesWritten) / Double(totalBytesExpected)) * 100)
            if shouldReport(percent: percent) {
                lastReportedPercent = percent
                print("[\(fileIndex)/\(totalFiles)] \(remotePath) \(percent)%")
            }
            return
        }

        let reportThreshold: Int64 = 50 * 1024 * 1024
        if totalBytesWritten - lastReportedBytes >= reportThreshold {
            lastReportedBytes = totalBytesWritten
            let sizeInMB = Double(totalBytesWritten) / 1_048_576
            let formattedSize = String(format: "%.1f", sizeInMB)
            print("[\(fileIndex)/\(totalFiles)] \(remotePath) \(formattedSize) MB")
        }
    }

    private func shouldReport(percent: Int) -> Bool {
        if percent >= 100 {
            return true
        }

        return percent >= lastReportedPercent + 10
    }
}

enum DownloaderError: LocalizedError {
    case accessDenied(String)
    case repositoryNotFound(String)
    case noFilesFound(String)
    case invalidResponse
    case httpFailure(Int)
    case networkFailure(String)
    case downloadFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let repoID):
            return "Access denied while downloading model repository \(repoID)."
        case .repositoryNotFound(let repoID):
            return "Model repository was not found: \(repoID)."
        case .noFilesFound(let repoID):
            return "No downloadable files were found for model repository \(repoID)."
        case .invalidResponse:
            return "Model download failed because the server returned an invalid response."
        case .httpFailure(let statusCode):
            return "Model download failed with HTTP status \(statusCode)."
        case .networkFailure(let details):
            return "Model download failed due to a network error: \(details)"
        case .downloadFailed(let path, let details):
            return "Model download failed for file \(path): \(details)"
        }
    }
}