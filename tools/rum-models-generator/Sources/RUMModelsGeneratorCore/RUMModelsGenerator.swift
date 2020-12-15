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
        self.init(
            name: url.lastPathComponent,
            content: try Data(contentsOf: url)
        )
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
    private let jsonSchemaReader = JSONSchemaReader()
    private let jsonObjectReader = JSONTypeReader()
    private let swiftStructReader = SwiftTypeReader()
    private let rumSwiftTransformer = RUMSwiftTypeTransformer()
    private let swiftPrinter = SwiftPrinter()

    public init() {}

    public func printRUMModels(for schemaFiles: RUMJSONSchemaFiles) throws -> String {
        var output = """
        /*
        * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
        * This product includes software developed at Datadog (https://www.datadoghq.com/).
        * Copyright 2019-2020 Datadog, Inc.
        */

        import Foundation

        internal protocol RUMDataModel: Codable {}

        """

        let mainSchemaFiles = [
            schemaFiles.viewSchema,
            schemaFiles.resourceSchema,
            schemaFiles.actionSchema,
            schemaFiles.errorSchema,
            schemaFiles.longTaskSchema
        ]

        try mainSchemaFiles.forEach { schemaFile in
            let jsonSchema = try jsonSchemaReader.readJSONSchema(
                from: schemaFile,
                resolvingAgainst: [schemaFiles.commonSchema]
            )
            let jsonObject = try jsonObjectReader.readJSONObject(from: jsonSchema)
            var swiftStruct = try swiftStructReader.readSwiftStruct(from: jsonObject)
            swiftStruct = rumSwiftTransformer.transform(type: swiftStruct) as! SwiftStruct // swiftlint:disable:this force_cast
            output += "\n"
            output += try swiftPrinter.print(swiftStruct: swiftStruct)
        }

        return output
    }
}
