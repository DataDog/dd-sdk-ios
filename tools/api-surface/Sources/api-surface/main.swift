/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import ArgumentParser
import APISurfaceCore

private struct RootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "api-surface",
        abstract: "Prints API surface for given Swift module.",
        subcommands: [
            SPMSurface.self,
            WorskspaceSurface.self
        ]
    )

    struct SPMSurface: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "spm",
            abstract: "Prints API surface for given SPM module."
        )

        @Option(help: "The name of Swift module.")
        var moduleName: String

        @Option(help: "The path to the folder containing `Package.swift`")
        var path: String

        func run() {
            do {
                let surface = try APISurface(forSPMModuleNamed: moduleName, inPath: path)
                print(surface.print())
            } catch {
                print("Failed to generate api surface: \(error)")
            }
        }
    }

    struct WorskspaceSurface: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "workspace",
            abstract: "Prints API surface for a module produced by given scheme in given workspace."
        )

        @Option(help: "The name of the workspace (including extension).")
        var workspaceName: String

        @Option(help: "The name of the scheme producing a Swift module.")
        var scheme: String

        @Option(help: "The path to the folder containing workspace file.")
        var path: String

        func run() {
            do {
                let surface = try APISurface(forWorkspaceNamed: workspaceName, scheme: scheme, inPath: path)
                print(surface.print())
            } catch {
                print("Failed to generate api surface: \(error)")
            }
        }
    }
}

RootCommand.main()
