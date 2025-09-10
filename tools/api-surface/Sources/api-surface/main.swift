/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import ArgumentParser
import APISurfaceCore

private struct RootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A tool to manage API surface files.",
        subcommands: [
            GenerateCommand.self,
            VerifyCommand.self
        ],
        defaultSubcommand: GenerateCommand.self
    )
}

RootCommand.main()
