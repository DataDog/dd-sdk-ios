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
        writeLine("\(configuration.accessLevel) struct \(swiftStruct.name)\(conformance) {")
        indentRight()
        try printPropertiesList(swiftStruct.properties)
        if swiftStruct.conforms(to: codableProtocol) {
            try printCodingKeys(for: swiftStruct.properties)
        }
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
            let name = property.name
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
                    throw Exception.unimplemented("Failed to print prooperty default value: \(value)")
                }
            }

            printComment(property.comment)
            writeLine("\(configuration.accessLevel) \(kind) \(name): \(type)\(optionality)\(defaultValue ?? "")")

            if index < properties.count - 1 {
                writeEmptyLine()
            }
        }
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
            writeLine("enum \(codingKeyEnumName): String, CodingKey {")
            indentRight()
            try staticallyCodedProperties
                .forEach { property in
                    guard case .static(let codingKeyValue) = property.codingKey else {
                        throw Exception.illegal("Expected `codingKey` to be `.static` for property `\(property.name)`")
                    }

                    writeLine("case \(property.name) = \"\(codingKeyValue)\"")
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
        let codedProperties = swiftStruct.properties.filter { $0.defaultValue == nil || $0.mutability != .immutable }
        let staticallyCodedProperties = codedProperties.filter { $0.codingKey.isStatic }
        let dynamicallyCodedProperties = codedProperties.filter { !$0.codingKey.isStatic }

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

            if !staticallyCodedProperties.isEmpty {
                writeLine("// Encode static properties:")
                writeLine("var staticContainer = encoder.container(keyedBy: StaticCodingKeys.self)")

                staticallyCodedProperties.forEach { staticProperty in
                    writeLine("try staticContainer.encodeIfPresent(\(staticProperty.name), forKey: .\(staticProperty.name))")
                }
            }

            if !staticallyCodedProperties.isEmpty && dynamicallyCodedProperty != nil {
                writeEmptyLine()
            }

            if let dynamicProperty = dynamicallyCodedProperty {
                writeLine("// Encode dynamic properties:")
                writeLine("var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)")

                guard dynamicProperty.type is SwiftDictionary else {
                    throw Exception.unimplemented("Printing dynamic property of type `\(dynamicProperty.type)` is not supported ")
                }

                writeLine("try \(dynamicProperty.name).forEach {") // dynamic properties are dictionaries
                indentRight()
                    writeLine("let key = DynamicCodingKey($0)") // dictionary key is used as coding key
                    writeLine("try dynamicContainer.encode(AnyEncodable($1), forKey: key)") // encode value
                indentLeft()
                writeLine("}")
            }

            indentLeft()
            writeLine("}")
        }

        func printDecodingImplemenation() throws {
            writeLine("\(configuration.accessLevel) init(from decoder: Decoder) throws {")
            indentRight()

            if !staticallyCodedProperties.isEmpty {
                writeLine("// Decode static properties:")
                writeLine("let staticContainer = try decoder.container(keyedBy: StaticCodingKeys.self)")

                try staticallyCodedProperties.forEach { staticProperty in
                    let type = try typeDeclaration(staticProperty.type)
                    if staticProperty.isOptional {
                        writeLine("self.\(staticProperty.name) = try staticContainer.decodeIfPresent(\(type).self, forKey: .\(staticProperty.name))")
                    } else {
                        writeLine("self.\(staticProperty.name) = try staticContainer.decode(\(type).self, forKey: .\(staticProperty.name))")
                    }
                }
            }

            if !staticallyCodedProperties.isEmpty && dynamicallyCodedProperty != nil {
                writeEmptyLine()
            }

            if let dynamicProperty = dynamicallyCodedProperty {
                writeLine("// Decode other properties into [String: Codable] dictionary:")
                writeLine("let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)")

                if !staticallyCodedProperties.isEmpty {
                    // If the type defines some static properties, treat other properties as dynamic
                    writeLine("let allStaticKeys = Set(staticContainer.allKeys.map { $0.stringValue })")
                    writeLine("let dynamicKeys = dynamicContainer.allKeys.filter { !allStaticKeys.contains($0.stringValue) }")
                } else {
                    // If the type doesn't define any static properties, treat all properties as dynamic
                    writeLine("let dynamicKeys = dynamicContainer.allKeys")
                }

                writeLine("var dictionary: [String: Codable] = [:]")
                writeEmptyLine()

                writeLine("try dynamicKeys.forEach { codingKey in")
                indentRight()
                // We use `dynamicContainer.decode()` instead of `dynamicContainer.decodeIfPresent()` to not lose
                // the information of decoded `null` value. Our `AnyCodable` implementation recognizes `null` and preserves
                // it for eventual encoding. This guarantees no difference in serialized payload even if we deserialize it
                // and encode again.
                writeLine("dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)")
                indentLeft()
                writeLine("}")

                writeEmptyLine()
                writeLine("self.\(dynamicProperty.name) = dictionary")
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
        writeLine("\(configuration.accessLevel) enum \(enumeration.name): \(rawValueType)\(conformance) {")
        indentRight()
        enumeration.cases.forEach { `case` in
            switch `case`.rawValue {
            case .string(let value):
                writeLine("case \(`case`.label) = \"\(value)\"")
            case .integer(let value):
                writeLine("case \(`case`.label) = \(value)")
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
                    writeLine("case .\(`case`.label)(let value):")
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
                        writeLine("self = .\(`case`.label)(value: value)")
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
        writeLine("\(configuration.accessLevel) enum \(enumeration.name)\(conformance) {")
        indentRight()
        try enumeration.cases.forEach { `case` in
            let associatedTypeDeclaration = try typeDeclaration(`case`.associatedType)
            writeLine("case \(`case`.label)(value: \(associatedTypeDeclaration))")
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
            writeLine("/// \(comment)")
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
        }
    }
}
