/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CodeGeneration
import CodeDecoration

internal func generateRUMSwiftModels(from schema: URL) throws -> String {
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

            public protocol RUMDataModel: Codable {}

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
        .decorate(using: RUMCodeDecorator())
        .print(using: template, and: printer)
}

internal func generateRUMObjcInteropModels(from schema: URL, skip typesToSkip: Set<String>) throws -> String {
    let generator = ModelsGenerator()

    let template = OutputTemplate(
        header: """
            /*
             * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
             * This product includes software developed at Datadog (https://www.datadoghq.com/).
             * Copyright 2019-Present Datadog, Inc.
             */

            import Foundation
            import DatadogInternal

            // This file was generated from JSON Schema. Do not modify it directly.

            // swiftlint:disable force_unwrapping

            """,
        footer: """

            // swiftlint:enable force_unwrapping

            """
    )
    let printer = ObjcInteropPrinter(objcTypeNamesPrefix: "objc_")

    return try generator
        .generateCode(from: schema)
        .skip(types: typesToSkip)
        .decorate(using: RUMCodeDecorator())
        .print(using: template, and: printer)
}
