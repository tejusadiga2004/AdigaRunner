// Author: Tejus Adiga M <entropypagesindia@gmail.com>
// Copyright (c) 2026 Tejus Adiga M. All rights reserved.

import Foundation

enum CLICommand {
    case serve(AppConfig)
    case listModels(modelsDirectory: URL)
    case listDownloadedModels(modelsDirectory: URL)
    case downloadModel(DownloadConfig)
}

struct AppConfig {
    let modelReference: String
    let modelPath: String
    let host: String
    let port: Int
    let defaultMaxTokens: Int
    let defaultTemperature: Double
    let modelsDirectory: URL

    static func parseCommand(from args: [String]) throws -> CLICommand {
        guard args.count >= 2 else {
            throw ConfigError.missingCommand
        }

        let command = args[1]

        switch command {
        case "--help", "-h":
            throw ConfigError.helpRequested
        case "list-models":
            let modelsDirectory = try parseModelsDirectory(from: Array(args.dropFirst(2)))
            return .listModels(modelsDirectory: modelsDirectory)
        case "list-available-models":
            let modelsDirectory = try parseModelsDirectory(from: Array(args.dropFirst(2)))
            return .listDownloadedModels(modelsDirectory: modelsDirectory)
        case "download-model":
            return .downloadModel(try DownloadConfig.parse(from: args))
        case "serve":
            return .serve(try parseServeConfig(from: args, modelArgumentIndex: 2))
        default:
            return .serve(try parseServeConfig(from: args, modelArgumentIndex: 1))
        }
    }

    private static func parseServeConfig(from args: [String], modelArgumentIndex: Int) throws -> AppConfig {
        guard args.count > modelArgumentIndex else {
            throw ConfigError.missingModelPath
        }

        let modelReference = args[modelArgumentIndex]
        var host = "127.0.0.1"
        var port = 8080
        var defaultMaxTokens = 256
        var defaultTemperature = 0.7
        var modelsDirectory = ModelStorage.defaultBaseDirectory()

        var index = modelArgumentIndex + 1
        while index < args.count {
            let flag = args[index]
            switch flag {
            case "--host":
                index += 1
                guard index < args.count else { throw ConfigError.missingValue(flag) }
                host = args[index]
            case "--port":
                index += 1
                guard index < args.count else { throw ConfigError.missingValue(flag) }
                guard let parsed = Int(args[index]), parsed > 0, parsed < 65536 else {
                    throw ConfigError.invalidValue(flag, args[index])
                }
                port = parsed
            case "--max-tokens":
                index += 1
                guard index < args.count else { throw ConfigError.missingValue(flag) }
                guard let parsed = Int(args[index]), parsed > 0, parsed <= 8192 else {
                    throw ConfigError.invalidValue(flag, args[index])
                }
                defaultMaxTokens = parsed
            case "--temperature":
                index += 1
                guard index < args.count else { throw ConfigError.missingValue(flag) }
                guard let parsed = Double(args[index]), parsed >= 0.0, parsed <= 2.0 else {
                    throw ConfigError.invalidValue(flag, args[index])
                }
                defaultTemperature = parsed
            case "--models-dir":
                index += 1
                guard index < args.count else { throw ConfigError.missingValue(flag) }
                modelsDirectory = URL(fileURLWithPath: args[index], isDirectory: true)
            case "--help", "-h":
                throw ConfigError.helpRequested
            default:
                throw ConfigError.unknownFlag(flag)
            }
            index += 1
        }

        let modelPath = try resolveModelPath(for: modelReference, modelsDirectory: modelsDirectory)

        return AppConfig(
            modelReference: modelReference,
            modelPath: modelPath,
            host: host,
            port: port,
            defaultMaxTokens: defaultMaxTokens,
            defaultTemperature: defaultTemperature,
            modelsDirectory: modelsDirectory
        )
    }

    private static func parseModelsDirectory(from args: [String]) throws -> URL {
        var modelsDirectory = ModelStorage.defaultBaseDirectory()
        var index = 0

        while index < args.count {
            let flag = args[index]
            switch flag {
            case "--models-dir":
                index += 1
                guard index < args.count else { throw ConfigError.missingValue(flag) }
                modelsDirectory = URL(fileURLWithPath: args[index], isDirectory: true)
            case "--help", "-h":
                throw ConfigError.helpRequested
            default:
                throw ConfigError.unknownFlag(flag)
            }
            index += 1
        }

        return modelsDirectory
    }

    private static func resolveModelPath(for modelReference: String, modelsDirectory: URL) throws -> String {
        if let supportedModel = SupportedModelCatalog.model(named: modelReference) {
            let localPath = ModelStorage.localPath(for: supportedModel, baseDirectory: modelsDirectory)
            guard FileManager.default.fileExists(atPath: localPath.path) else {
                throw ConfigError.modelNotDownloaded(supportedModel.name, localPath.path)
            }

            return localPath.path
        }

        return modelReference
    }
}

struct DownloadConfig {
    let model: SupportedModel
    let modelsDirectory: URL

    static func parse(from args: [String]) throws -> DownloadConfig {
        guard args.count >= 3 else {
            throw ConfigError.missingDownloadModelName
        }

        let modelName = args[2]
        guard let model = SupportedModelCatalog.model(named: modelName) else {
            throw ConfigError.unsupportedModel(modelName)
        }

        var modelsDirectory = ModelStorage.defaultBaseDirectory()
        var index = 3

        while index < args.count {
            let flag = args[index]
            switch flag {
            case "--models-dir":
                index += 1
                guard index < args.count else { throw ConfigError.missingValue(flag) }
                modelsDirectory = URL(fileURLWithPath: args[index], isDirectory: true)
            case "--help", "-h":
                throw ConfigError.helpRequested
            default:
                throw ConfigError.unknownFlag(flag)
            }
            index += 1
        }

        return DownloadConfig(model: model, modelsDirectory: modelsDirectory)
    }
}

enum ConfigError: LocalizedError {
    case missingCommand
    case missingModelPath
    case missingDownloadModelName
    case missingValue(String)
    case invalidValue(String, String)
    case unknownFlag(String)
    case unsupportedModel(String)
    case modelNotDownloaded(String, String)
    case helpRequested

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            return usageText
        case .missingModelPath:
            return "Missing model name or model path. \(usageText)"
        case .missingDownloadModelName:
            return "Missing supported model name for download-model. \(usageText)"
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value '\(value)' for \(flag)."
        case .unknownFlag(let flag):
            return "Unknown argument: \(flag)."
        case .unsupportedModel(let name):
            return "Unsupported model '\(name)'. Use 'adiga list-models' to see supported models."
        case .modelNotDownloaded(let name, let path):
            return "Supported model '\(name)' is not downloaded locally at \(path). Run 'adiga download-model \(name)' first."
        case .helpRequested:
            return usageText
        }
    }

    private var usageText: String {
        Self.usageText
    }

    private static let usageText = "Usage:\n  adiga list-models [--models-dir <path>]\n  adiga list-available-models [--models-dir <path>]\n  adiga download-model <model-name> [--models-dir <path>]\n  adiga serve <model-name|model-path> [--host 127.0.0.1] [--port 8080] [--max-tokens 256] [--temperature 0.7] [--models-dir <path>]\n  adiga <model-name|model-path> [--host 127.0.0.1] [--port 8080] [--max-tokens 256] [--temperature 0.7] [--models-dir <path>]"
}
