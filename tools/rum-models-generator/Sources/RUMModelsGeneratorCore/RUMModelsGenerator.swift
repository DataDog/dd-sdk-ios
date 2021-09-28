/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

public struct File {
    internal let name: String
    internal let content: Data
}

public extension File {
    init(url: URL) throws {
        self.name = url.lastPathComponent
        self.content = try Data(contentsOf: url)
    }
}

public struct RUMJSONSchemaFiles {
    internal let commonSchema: File
    internal let actionSchema: File
    internal let errorSchema: File
    internal let longTaskSchema: File
    internal let resourceSchema: File
    internal let viewSchema: File
}

public extension RUMJSONSchemaFiles {
    init(folder url: URL) throws {
        self.init(
            commonSchema: try File(url: url.appendingPathComponent("_common-schema.json")),
            actionSchema: try File(url: url.appendingPathComponent("action-schema.json")),
            errorSchema: try File(url: url.appendingPathComponent("error-schema.json")),
            longTaskSchema: try File(url: url.appendingPathComponent("long_task-schema.json")),
            resourceSchema: try File(url: url.appendingPathComponent("resource-schema.json")),
            viewSchema: try File(url: url.appendingPathComponent("view-schema.json"))
        )
    }
}

public class RUMModelsGenerator {
    public enum Printer {
        /// Swift code printer.
        case swift
        /// `@objc` interop Swift code printer.
        case objcInterop
    }

    public init() {}

    public func printRUMModels(
        for schemaFiles: RUMJSONSchemaFiles,
        using printer: Printer
    ) throws -> String {
        let mainSchemaFiles = [
            schemaFiles.viewSchema,
            schemaFiles.resourceSchema,
            schemaFiles.actionSchema,
            schemaFiles.errorSchema,
            schemaFiles.longTaskSchema,
        ]

        // Read ambiguous JSON schemas from `*.json` files
        let jsonSchemas = try JSONSchemaReader().readJSONSchemas(
            from: mainSchemaFiles,
            resolvingAgainst: [schemaFiles.commonSchema]
        )

        // Transform into type-safe JSONObjects
        let jsonObjects = try JSONSchemaToJSONTypeTransformer().transform(jsonSchemas: jsonSchemas)

        // Transform into type-safe SwiftType schemas
        let swiftTypes = try JSONToSwiftTypeTransformer().transform(jsonObjects: jsonObjects)

        // Apply RUM models customization (e.g. naming conventions) to SwiftType schemas
        let rumModels = try RUMSwiftTypeTransformer().transform(types: swiftTypes)

        // Print code
        switch printer {
        case .swift:
            return try printSwiftCode(for: rumModels)
        case .objcInterop:
            let objcInteropRUMModels = try SwiftToObjcInteropTypeTransformer()
                .transform(swiftTypes: rumModels)
            return try printObjcInteropCode(for: objcInteropRUMModels)
        }
    }

    private func printSwiftCode(for rumModels: [SwiftType]) throws -> String {
        var output = """
        /*
         * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
         * This product includes software developed at Datadog (https://www.datadoghq.com/).
         * Copyright 2019-2020 Datadog, Inc.
         */

        // This file was generated from JSON Schema. Do not modify it directly.

        internal protocol RUMDataModel: Codable {}

        """

        output += try SwiftPrinter().print(swiftTypes: rumModels)
        return output
    }

    private func printObjcInteropCode(for rumModels: [ObjcInteropType]) throws -> String {
        var output = """
        /*
         * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
         * This product includes software developed at Datadog (https://www.datadoghq.com/).
         * Copyright 2019-2020 Datadog, Inc.
         */

        import Datadog
        import Foundation

        // This file was generated from JSON Schema. Do not modify it directly.

        // swiftlint:disable force_unwrapping

        """

        output += try ObjcInteropPrinter(objcTypeNamesPrefix: "DD").print(objcInteropTypes: rumModels)
        output += """

        // swiftlint:enable force_unwrapping

        """
        return output
    }
}
