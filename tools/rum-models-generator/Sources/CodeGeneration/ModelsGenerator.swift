/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Generates code from provided JSON schema file.
public struct ModelsGenerator {
    public init() {}

    /// Generates code from JSON schema file.
    /// - Parameter schemaFileURL: the URL of schema file
    /// - Returns: schema for generated code.
    public func generateCode(from schemaFileURL: URL) throws -> GeneratedCode {
        let jsonSchema = try JSONSchemaReader().read(schemaFileURL)
        let jsonType = try JSONSchemaToJSONTypeTransformer().transform(jsonSchema: jsonSchema)
        let swiftTypes = try JSONToSwiftTypeTransformer().transform(jsonType: jsonType)
        return GeneratedCode(swiftTypes: swiftTypes)
    }
}

/// Schema describing generated code.
public struct GeneratedCode {
    /// An array of Swift schemas describing root constructs in generated code.
    public let swiftTypes: [SwiftType]

    /// Changes this schema by applying provided decoration.
    /// It can be used to adjust naming and structure of generated code.
    public func decorate(using decorator: CodeDecorator) throws -> GeneratedCode {
        return try decorator.decorate(code: self)
    }

    /// Sorts types alphabetically by name.
    /// - Returns: a new schema with sorted types
    ///
    /// The resulting order is:
    /// 1. Named types (structs, enums) sorted alphabetically by name
    /// 2. Other types (primitives, etc.), preserving their original order
    public func sortTypes() -> GeneratedCode {
        var namedTypes: [SwiftType] = []
        var otherTypes: [SwiftType] = []

        // Separate types into named types and other types
        for type in swiftTypes {
            if type.typeName != nil {
                namedTypes.append(type)
            } else {
                otherTypes.append(type)
            }
        }

        // Sort named types alphabetically
        namedTypes.sort { lhs, rhs in
            let lhsName = lhs.typeName! // swiftlint:disable:this force_unwrapping
            let rhsName = rhs.typeName! // swiftlint:disable:this force_unwrapping
            return lhsName < rhsName
        }

        // Combine all types in the desired order
        let sortedTypes = namedTypes + otherTypes

        return GeneratedCode(swiftTypes: sortedTypes)
    }

    /// Skips list of types which should not be included in generated code.
    /// - Parameter types: a set of type names to skip
    /// - Returns: a new schema with skipped types.
    public func skip(types typesToSkip: Set<String>) -> GeneratedCode {
        let filteredTypes = swiftTypes.filter {
            guard let typeName = $0.typeName else {
                return true
            }
            return !typesToSkip.contains(typeName)
        }
        return GeneratedCode(swiftTypes: filteredTypes)
    }

    /// Renders generated code with provided template.
    public func print(using template: OutputTemplate, and printer: CodePrinter) throws -> String {
        let codeText = try printer.print(code: self)
        return template.render(code: codeText)
    }

    public init(swiftTypes: [SwiftType]) {
        self.swiftTypes = swiftTypes
    }
}

/// A type decorating generated code.
/// Decoration can be used to adjust naming and structure in generated code before it is printed.
public protocol CodeDecorator {
    func decorate(code: GeneratedCode) throws -> GeneratedCode
}

/// The template for generated code file.
public struct OutputTemplate {
    let header: String
    let footer: String

    /// Initializer.
    /// - Parameters:
    ///   - header: a text block to put before generated code
    ///   - footer: a text block to put after generated code
    public init(header: String, footer: String) {
        self.header = header
        self.footer = footer
    }

    func render(code: String) -> String {
        return [header, code, footer].joined()
    }
}

/// Prints generated code.
public protocol CodePrinter {
    func print(code: GeneratedCode) throws -> String
}
