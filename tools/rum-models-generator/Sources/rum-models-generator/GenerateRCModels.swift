/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CodeGeneration
import CodeDecoration

internal func generateRCSwiftModels(from schema: URL) throws -> String {
    let generator = ModelsGenerator()

    let template = OutputTemplate(
        header: """
            /*
             * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
             * This product includes software developed at Datadog (https://www.datadoghq.com/).
             * Copyright 2019-Present Datadog, Inc.
             */

            // This file was generated from JSON Schema. Do not modify it directly.

            // swiftlint:disable all

            """,
        footer: ""
    )
    let printer = SwiftPrinter(
        configuration: .init(
            accessLevel: .public
        )
    )

    return try generator
        .generateCode(from: schema)
        .decorate(using: RCCodeDecorator())
        .sortTypes()
        .print(using: template, and: printer)
}
