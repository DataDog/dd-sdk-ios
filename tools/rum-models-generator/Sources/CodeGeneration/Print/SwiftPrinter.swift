/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Generates Swift code from `SwiftTypes`.
public class SwiftPrinter: BasePrinter, CodePrinter {
    public struct Configuration {
        public enum AccessLevel {
            /// Use to make all generated models visible in public interface.
            case `public`
            /// Use to make all generated models visible in internal interface.
            case `internal`
            case `spi`
        }

        /// Access level for for entities within printed code.
        public let accessLevel: AccessLevel

        public init(accessLevel: AccessLevel = .public) {
            self.accessLevel = accessLevel
        }
    }

    /// Configuration for printing code.
    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - CodePrinter

    public func print(code: GeneratedCode) throws -> String {
        return try print(swiftTypes: code.swiftTypes)
    }

    // MARK: - Internal

    internal func print(swiftTypes: [SwiftType]) throws -> String {
        reset()

        try swiftTypes.forEach { type in
            writeEmptyLine()
            if let `struct` = type as? SwiftStruct {
                try printStruct(`struct`)
                try printExtensionsWithCodableImplementation(`struct`)
            } else if let `enum` = type as? SwiftEnum {
                try printEnum(`enum`)
            } else if let associatedTypeEnum = type as? SwiftAssociatedTypeEnum {
                try printAssociatedTypeEnum(associatedTypeEnum)
            } else {
                throw Exception.illegal("\(type) cannot be printed as root declaration.")
            }
        }

        return output
    }

    // MARK: - Private

    private func printStruct(_ swiftStruct: SwiftStruct) throws {
        let implementedProtocols = swiftStruct.conformance.map { $0.name }
        let conformance = implementedProtocols.isEmpty ? "" : ": \(implementedProtocols.joined(separator: ", "))"

        printComment(swiftStruct.comment)
        if let attribute = configuration.accessLevel.attribute {
            writeLine("\(attribute)")
        }
        writeLine("\(configuration.accessLevel) struct \(swiftStruct.name)\(conformance) {")
        indentRight()
        try printPropertiesList(swiftStruct.properties)
        if swiftStruct.conforms(to: codableProtocol) {
            try printCodingKeys(for: swiftStruct.properties)
        }

        writeEmptyLine()
        try printInit(swiftStruct)
        try printNestedTypes(in: swiftStruct)
        indentLeft()
        writeLine("}")
    }

    private func printPropertiesList(_ properties: [SwiftStruct.Property]) throws {
        try properties.enumerated().forEach { index, property in
            let kind: String
            switch property.mutability {
            case .mutable: kind = "var"
            case .mutableInternally: kind = "internal(set) var"
            case .immutable: kind = "let"
            }
            let name = property.backtickName
            let type = try typeDeclaration(property.type)
            let optionality = property.isOptional ? "?" : ""
            let defaultValue: String? = try property.defaultValue.ifNotNil { value in
                switch value {
                case let integerValue as Int:
                    return " = \(integerValue)"
                case let stringValue as String:
                    return " = \"\(stringValue)\""
                case let enumValue as SwiftEnum.Case:
                    return " = .\(enumValue.label)"
                default:
                    throw Exception.unimplemented("Failed to print property default value: \(value)")
                }
            }

            printComment(property.comment)
            writeLine("\(configuration.accessLevel) \(kind) \(name): \(type)\(optionality)\(defaultValue ?? "")")

            if index < properties.count - 1 {
                writeEmptyLine()
            }
        }
    }

    private func printInit(_ swiftStruct: SwiftStruct) throws {
        let properties = swiftStruct.properties.filter { $0.defaultValue == nil }

        printComment(swiftStruct.comment)
        guard !properties.isEmpty else {
            writeLine("\(configuration.accessLevel) init() { }")
            return
        }

        writeLine("///")
        printComment("- Parameters:")
        properties.enumerated().forEach { index, property in
            printComment("  - \(property.backtickName):\(property.comment.map { " \($0)" } ?? "")")
        }

        writeLine("\(configuration.accessLevel) init(")
        indentRight()
        try properties.enumerated().forEach { index, property in
            let name = property.backtickName
            let type = try typeDeclaration(property.type)
            let optionality = property.isOptional ? "? = nil" : ""
            let separator = index < properties.count - 1 ? "," : ""
            writeLine("\(name): \(type)\(optionality)\(separator)")
        }

        indentLeft()
        writeLine(") {")
        indentRight()

        properties.enumerated().forEach { index, property in
            let name = property.backtickName
            writeLine("self.\(name) = \(name)")
        }

        indentLeft()
        writeLine("}")
    }

    /// Prints `CodingKeys` for given properties.
    ///
    /// This includes stically coded properties (where `Codable` conformance is compiler-generated) and dynamically coded
    /// properties (where `Codable` conformance is printed later in separate `extension`).
    private func printCodingKeys(for properties: [SwiftStruct.Property]) throws {
        let staticallyCodedProperties = properties.filter { $0.codingKey.isStatic }
        let hasStaticallyCodedProperties = properties.contains { $0.codingKey.isStatic }
        let hasDynamicallyCodedProperties = properties.contains { !$0.codingKey.isStatic }

        func printStaticCodingKeys(named codingKeyEnumName: String) throws {
            writeEmptyLine()
            writeLine("\(configuration.accessLevel) enum \(codingKeyEnumName): String, CodingKey {")
            indentRight()
            try staticallyCodedProperties
                .forEach { property in
                    guard case .static(let codingKeyValue) = property.codingKey else {
                        throw Exception.illegal("Expected `codingKey` to be `.static` for property `\(property.name)`")
                    }

                    writeLine("case \(property.backtickName) = \"\(codingKeyValue)\"")
                }
            indentLeft()
            writeLine("}")
        }

        if hasStaticallyCodedProperties && !hasDynamicallyCodedProperties {
            // If the `struct` has no dynamically coded properties, its `Codable` conformance will
            // be generated by the compiler and we only need to list coding keys in `CodingKeys` enum.
            try printStaticCodingKeys(named: "CodingKeys")
        } else {
            // If the `struct` has some dynamically coded properties, the `Codable` conformance will be printed later in `extension`.
            // Static properties will be encoded using custom `StaticCodingKeys` enum and dynamic ones using `DynamicCodingKey`.
            if hasStaticallyCodedProperties {
                try printStaticCodingKeys(named: "StaticCodingKeys")
            }
        }
    }

    /// Prints`Codable` conformance in extension.
    ///
    /// This will only be effective for types that support dynamically coded properties. If all properties are statically coded,
    /// the `Codable` implementation is generated by compiler.
    private func printExtensionsWithCodableImplementation(_ swiftStruct: SwiftStruct, parentSwiftStructs: [SwiftStruct] = []) throws {
        let staticallyEncodedProperties = swiftStruct.properties.filter { $0.codingKey.isStatic }
        let staticallyDecodedProperties = staticallyEncodedProperties.filter { $0.defaultValue == nil || $0.mutability != .immutable }
        // ^ Exclude constant properties (e.g. `let foo = "default value"`) from decoding.
        // ^^ Otherwise it will result with compiler error: `Immutable value may only be initialized once`.
        let dynamicallyCodedProperties = swiftStruct.properties.filter { !$0.codingKey.isStatic }

        guard dynamicallyCodedProperties.count < 2 else {
            throw Exception.illegal(
                """
                There can be 0 or 1 dynamically coded property. Received \(dynamicallyCodedProperties.count):
                \(dynamicallyCodedProperties.map({ "- \($0.name)\n" }))
                """
            )
        }

        let dynamicallyCodedProperty = dynamicallyCodedProperties.first

        func printEncodingImplemenation() throws {
            writeLine("\(configuration.accessLevel) func encode(to encoder: Encoder) throws {")
            indentRight()

            if !staticallyEncodedProperties.isEmpty {
                writeLine("// Encode static properties:")
                writeLine("var staticContainer = encoder.container(keyedBy: StaticCodingKeys.self)")

                staticallyEncodedProperties.forEach { staticProperty in
                    let name = staticProperty.backtickName
                    writeLine("try staticContainer.encodeIfPresent(\(name), forKey: .\(name))")
                }
            }

            if !staticallyEncodedProperties.isEmpty && dynamicallyCodedProperty != nil {
                writeEmptyLine()
            }

            if let dynamicProperty = dynamicallyCodedProperty {
                writeLine("// Encode dynamic properties:")
                writeLine("var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)")

                guard let dict = dynamicProperty.type as? SwiftDictionary else {
                    throw Exception.unimplemented("Printing dynamic property of type `\(dynamicProperty.type)` is not supported ")
                }

                let value: String
                switch dict.value {
                case is SwiftEncodable, is SwiftCodable:
                    value = "AnyEncodable($1)"
                default:
                    value = "$1"
                }

                writeLine("try \(dynamicProperty.backtickName).forEach {") // dynamic properties are dictionaries
                indentRight()
                    writeLine("try dynamicContainer.encode(\(value), forKey: DynamicCodingKey($0))") // encode `value` (dictionary `key` is used as coding key)
                indentLeft()
                writeLine("}")
            }

            indentLeft()
            writeLine("}")
        }

        func printDecodingImplemenation() throws {
            writeLine("\(configuration.accessLevel) init(from decoder: Decoder) throws {")
            indentRight()

            if !staticallyDecodedProperties.isEmpty {
                writeLine("// Decode static properties:")
                writeLine("let staticContainer = try decoder.container(keyedBy: StaticCodingKeys.self)")

                try staticallyDecodedProperties.forEach { staticProperty in
                    let type = try typeDeclaration(staticProperty.type)
                    let name = staticProperty.backtickName
                    if staticProperty.isOptional {
                        writeLine("self.\(name) = try staticContainer.decodeIfPresent(\(type).self, forKey: .\(name))")
                    } else {
                        writeLine("self.\(name) = try staticContainer.decode(\(type).self, forKey: .\(name))")
                    }
                }
            }

            if !staticallyDecodedProperties.isEmpty && dynamicallyCodedProperty != nil {
                writeEmptyLine()
            }

            if let dynamicProperty = dynamicallyCodedProperty {
                guard let dict = dynamicProperty.type as? SwiftDictionary else {
                    throw Exception.unimplemented("Printing dynamic property of type `\(dynamicProperty.type)` is not supported ")
                }

                let valueType: String
                switch dict.value {
                case is SwiftEncodable, is SwiftCodable:
                    valueType = "AnyCodable"
                default:
                    valueType = try typeDeclaration(dict.value)
                }

                writeLine("// Decode other properties into [String: \(valueType)] dictionary:")
                writeLine("let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)")
                writeLine("self.\(dynamicProperty.name) = [:]")

                writeEmptyLine()

                if !staticallyDecodedProperties.isEmpty {
                    // If the type defines some static properties, treat other properties as dynamic
                    writeLine("let allStaticKeys = Set(staticContainer.allKeys.map { $0.stringValue })")
                    writeLine("try dynamicContainer.allKeys.filter { !allStaticKeys.contains($0.stringValue) }.forEach {")
                } else {
                    // If the type doesn't define any static properties, treat all properties as dynamic
                    writeLine("try dynamicContainer.allKeys.forEach {")
                }

                indentRight()
                // We use `dynamicContainer.decode()` instead of `dynamicContainer.decodeIfPresent()` to not lose
                // the information of decoded `null` value. Our `AnyCodable` implementation recognizes `null` and preserves
                // it for eventual encoding. This guarantees no difference in serialized payload even if we deserialize it
                // and encode again.
                writeLine("self.\(dynamicProperty.name)[$0.stringValue] = try dynamicContainer.decode(\(valueType).self, forKey: $0)")
                indentLeft()
                writeLine("}")
            }

            indentLeft()
            writeLine("}")
        }

        if dynamicallyCodedProperty != nil {
            // If the type has at least one dynamically coded property, its `Codable` conformance must be generated

            let typeName: String

            if parentSwiftStructs.isEmpty {
                typeName = swiftStruct.name
            } else {
                typeName = "\(parentSwiftStructs.map({ $0.name }).joined(separator: ".")).\(swiftStruct.name)"
            }

            writeEmptyLine()
            writeLine("extension \(typeName) {")
            indentRight()
                try printEncodingImplemenation()
                writeEmptyLine()
                try printDecodingImplemenation()
            indentLeft()
            writeLine("}")
        }

        // Continue for nested structs:
        let nestedTypes = swiftStruct.properties.map { $0.type }
        try nestedTypes.forEach { type in
            if let nestedStruct = (type as? SwiftStruct) ?? ((type as? SwiftArray)?.element as? SwiftStruct) {
                try printExtensionsWithCodableImplementation(nestedStruct, parentSwiftStructs: parentSwiftStructs + [swiftStruct])
            }
        }
    }

    private func printEnum(_ enumeration: SwiftEnum) throws {
        let implementedProtocols = enumeration.conformance.map { $0.name }
        let conformance = implementedProtocols.isEmpty ? "" : ", \(implementedProtocols.joined(separator: ", "))"
        let rawValueType: String = try {
            let firstCase = try enumeration.cases.first.unwrapOrThrow(.illegal("\(enumeration.name) enum has 0 cases"))
            switch firstCase.rawValue {
            case .string: return "String"
            case .integer: return "Int"
            }
        }()

        printComment(enumeration.comment)
        if let attribute = configuration.accessLevel.attribute {
            writeLine("\(attribute)")
        }
        writeLine("\(configuration.accessLevel) enum \(enumeration.name): \(rawValueType)\(conformance) {")
        indentRight()
        enumeration.cases.forEach { `case` in
            switch `case`.rawValue {
            case .string(let value):
                writeLine("case \(`case`.backtickLabel) = \"\(value)\"")
            case .integer(let value):
                writeLine("case \(`case`.backtickLabel) = \(value)")
            }
        }
        indentLeft()
        writeLine("}")
    }

    private func printAssociatedTypeEnum(_ enumeration: SwiftAssociatedTypeEnum) throws {
        func printEncodingImplemenation() {
            writeLine("\(configuration.accessLevel) func encode(to encoder: Encoder) throws {")
            indentRight()
                writeLine("// Encode only the associated value, without encoding enum case")
                writeLine("var container = encoder.singleValueContainer()")
                writeEmptyLine()
                writeLine("switch self {")

                enumeration.cases.forEach { `case` in
                    writeLine("case .\(`case`.backtickLabel)(let value):")
                    indentRight()
                        writeLine("try container.encode(value)")
                    indentLeft()
                }

            writeLine("}")
            indentLeft()
            writeLine("}")
        }

        func printDecodingImplemenation() throws {
            writeLine("\(configuration.accessLevel) init(from decoder: Decoder) throws {")
            indentRight()
                writeLine("// Decode enum case from associated value")
                writeLine("let container = try decoder.singleValueContainer()")
                writeEmptyLine()

                try enumeration.cases.forEach { `case` in
                    writeLine("if let value = try? container.decode(\(try typeDeclaration(`case`.associatedType)).self) {")
                    indentRight()
                        writeLine("self = .\(`case`.backtickLabel)(value: value)")
                        writeLine("return")
                    indentLeft()
                    writeLine("}")
                }

                writeLine("let error = DecodingError.Context(")
                indentRight()
                    writeLine("codingPath: container.codingPath,")
                    writeLine("debugDescription: \"\"\"")
                    writeLine("Failed to decode `\(enumeration.name)`.")
                    writeLine("Ran out of possibilities when trying to decode the value of associated type.")
                    writeLine("\"\"\"")
                indentLeft()
                writeLine(")")
                writeLine("throw DecodingError.typeMismatch(\(enumeration.name).self, error)")

            indentLeft()
            writeLine("}")
        }

        let implementedProtocols = enumeration.conformance.map { $0.name }
        let conformance = implementedProtocols.isEmpty ? "" : ": \(implementedProtocols.joined(separator: ", "))"

        printComment(enumeration.comment)
        if let attribute = configuration.accessLevel.attribute {
            writeLine("\(attribute)")
        }
        writeLine("\(configuration.accessLevel) enum \(enumeration.name)\(conformance) {")
        indentRight()
        try enumeration.cases.forEach { `case` in
            let associatedTypeDeclaration = try typeDeclaration(`case`.associatedType)
            writeLine("case \(`case`.backtickLabel)(value: \(associatedTypeDeclaration))")
        }

        if enumeration.conforms(to: codableProtocol) {
            writeEmptyLine()
            writeLine("// MARK: - Codable")
            writeEmptyLine()
            printEncodingImplemenation()
            writeEmptyLine()
            try printDecodingImplemenation()
        }

        try printNestedTypes(in: enumeration)
        indentLeft()
        writeLine("}")
    }

    // MARK: - Printing nested types

    private func printNestedTypes(in swiftStruct: SwiftStruct) throws {
        let nestedTypes = swiftStruct.properties.map { $0.type }
        try print(nestedTypes: nestedTypes)
    }

    private func printNestedTypes(in swiftAssociatedTypeEnum: SwiftAssociatedTypeEnum) throws {
        let nestedTypes = swiftAssociatedTypeEnum.cases.map { $0.associatedType }
        try print(nestedTypes: nestedTypes)
    }

    private func print(nestedTypes: [SwiftType]) throws {
        try nestedTypes.forEach { type in
            let nestedStruct = (type as? SwiftStruct) ?? ((type as? SwiftArray)?.element as? SwiftStruct)
            let nestedEnum = (type as? SwiftEnum) ?? ((type as? SwiftArray)?.element as? SwiftEnum)
            let nestedAssociatedTypeEnum = (type as? SwiftAssociatedTypeEnum) ?? ((type as? SwiftArray)?.element as? SwiftAssociatedTypeEnum)

            if let nestedStruct = nestedStruct {
                writeEmptyLine()
                try printStruct(nestedStruct)
            } else if let nestedEnum = nestedEnum {
                writeEmptyLine()
                try printEnum(nestedEnum)
            } else if let nestedAssociatedTypeEnum = nestedAssociatedTypeEnum {
                writeEmptyLine()
                try printAssociatedTypeEnum(nestedAssociatedTypeEnum)
            }
        }
    }

    // MARK: - Helpers

    private func printComment(_ comment: String?) {
        comment.ifNotNil { comment in
            // Split comment by newlines and prefix each line with "/// "
            let lines = comment.components(separatedBy: .newlines)
            for line in lines {
                if line.isEmpty {
                    writeLine("///")
                } else {
                    writeLine("/// \(line)")
                }
            }
        }
    }

    private func typeDeclaration(_ type: SwiftType) throws -> String {
        switch type {
        case is SwiftPrimitive<Bool>:
            return "Bool"
        case is SwiftPrimitive<Double>:
            return "Double"
        case is SwiftPrimitive<Int>:
            return "Int"
        case is SwiftPrimitive<Int64>:
            return "Int64"
        case is SwiftPrimitive<String>:
            return "String"
        case is SwiftCodable:
            return "Codable"
        case is SwiftEncodable:
            return "Encodable"
        case let swiftArray as SwiftArray:
            return "[\(try typeDeclaration(swiftArray.element))]"
        case let swiftDictionary as SwiftDictionary:
            return "[\(try typeDeclaration(swiftDictionary.key)): \(try typeDeclaration(swiftDictionary.value))]"
        case let swiftEnum as SwiftEnum:
            return swiftEnum.name
        case let swiftAssociatedTypeEnum as SwiftAssociatedTypeEnum:
            return swiftAssociatedTypeEnum.name
        case let swiftStruct as SwiftStruct:
            return swiftStruct.name
        case let swiftTypeReference as SwiftTypeReference:
            return swiftTypeReference.referencedTypeName
        default:
            throw Exception.unimplemented("Printing \(type) is not implemented.")
        }
    }
}

// MARK: - Convenience

extension SwiftPrinter.Configuration.AccessLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .public:
            return "public"
        case .internal:
            return "internal"
        case .spi:
            return "public"
        }
    }

    public var attribute: String? {
        switch self {
        case .public:
            return nil
        case .internal:
            return nil
        case .spi:
            return "@_spi(Internal)"
        }
    }
}

extension SwiftStruct.Property {
    var backtickName: String { backtickEscape(name) }
}

extension SwiftEnum.Case {
    var backtickLabel: String { backtickEscape(label) }
}

extension SwiftAssociatedTypeEnum.Case {
    var backtickLabel: String { backtickEscape(label) }
}

private func backtickEscape(_ name: String) -> String {
    if swiftReservedKeywords.contains(name) {
        return "`\(name)`"
    }

    return name
}

/// Non-exhaustive Swift reserved keywords as defined in:
/// https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/#Keywords-and-Punctuation
private let swiftReservedKeywords = [
    "associatedtype",
    "borrowing",
    "class",
    "consuming",
    "deinit",
    "enum",
    "extension",
    "fileprivate",
    "func",
    "import",
    "init",
    "inout",
    "internal",
    "let",
    "nonisolated",
    "open",
    "operator",
    "private",
    "precedencegroup",
    "protocol",
    "public",
    "rethrows",
    "static",
    "struct",
    "subscript",
    "typealias",
    "var"
]
