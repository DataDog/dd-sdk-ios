/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import ArgumentParser
import RUMModelsGeneratorCore
import Foundation

private struct RootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generates rum models from `rum-events-format` schema files and prints it to the standard output.",
        subcommands: [
            GenerateSwift.self,
            GenerateObjc.self
        ]
    )

    struct GenerateSwift: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "generate-swift",
            abstract: "Generates models for Datadog Swift."
        )

        @Option(help: "The path to the folder containing `rum-events-format` schemas.")
        var path: String

        func run() {
            do {
                let schemasFolderURL = URL(fileURLWithPath: path)
                let schemas = try RUMJSONSchemaFiles(folder: schemasFolderURL)
                let generator = RUMModelsGenerator()
                print(try generator.printRUMModels(for: schemas, using: .swift))
            } catch {
                print("Failed to generate Swift models: \(error)")
            }
        }
    }

    struct GenerateObjc: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "generate-objc",
            abstract: "Generates models for Datadog Objc."
        )

        @Option(help: "The path to the folder containing `rum-events-format` schemas.")
        var path: String

        func run() {
            do {
                let schemasFolderURL = URL(fileURLWithPath: path)
                let schemas = try RUMJSONSchemaFiles(folder: schemasFolderURL)
                let generator = RUMModelsGenerator()
                print(try generator.printRUMModels(for: schemas, using: .objcInterop))
            } catch {
                print("Failed to generate Objc models: \(error)")
            }
        }
    }
}

RootCommand.main()
