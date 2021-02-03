/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Generates Swift code from `SwiftTypes`.
public class SwiftPrinter: BasePrinter {
    public func print(swiftTypes: [SwiftType]) throws -> String {
        reset()

        writeEmptyLine()
        printDynamicCodingKeys()

        try swiftTypes.forEach { type in
            writeEmptyLine()
            if let `struct` = type as? SwiftStruct {
                try printStruct(`struct`)
            } else if let `enum` = type as? SwiftEnum {
                try printEnum(`enum`)
            } else {
                throw Exception.illegal("\(type) cannot be printed as root declaration.")
            }
        }

        return output
    }

    // MARK: - Private

    private func printDynamicCodingKeys() {
        let code = """
        fileprivate struct DynamicCodingKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
            init(_ string: String) { self.stringValue = string }
        }
        """
        writeLine(code)
    }

    private func printStruct(_ swiftStruct: SwiftStruct) throws {
        let implementedProtocols = swiftStruct.conformance.map { $0.name }
        let conformance = implementedProtocols.isEmpty ? "" : ": \(implementedProtocols.joined(separator: ", "))"

        printComment(swiftStruct.comment)
        writeLine("public struct \(swiftStruct.name)\(conformance) {")
        indentRight()
        try printPropertiesList(swiftStruct.properties)
        try printAdditionalProperties(swiftStruct.additionalProperties)
        if swiftStruct.conforms(to: codableProtocol) {
            printCodingKeys(for: swiftStruct.properties)
            if let additionalProperties = swiftStruct.additionalProperties {
                try printCodableMethods(
                    for: swiftStruct.properties,
                    additionalProperties: additionalProperties
                )
            }
        }
        try printNestedTypes(in: swiftStruct)
        indentLeft()
        writeLine("}")
    }

    private func printComment(_ comment: String?) {
        comment.ifNotNil { comment in
            writeLine("/// \(comment)")
        }
    }

    private func printPropertiesList(_ properties: [SwiftStruct.Property]) throws {
        try properties.enumerated().forEach { index, property in
            let accessLevel = "public"
            let kind = property.isMutable ? "var" : "let"
            let name = property.name
            let type = try typeDeclaration(property.type)
            let optionality = property.isOptional ? "?" : ""
            let defaultValue = try defaultValueDeclaration(property)
            let line = "\(accessLevel) \(kind) \(name): \(type)\(optionality)\(defaultValue ?? "")"

            printComment(property.comment)
            writeLine(line)

            if index < properties.count - 1 {
                writeEmptyLine()
            }
        }
    }

    private func printAdditionalProperties(_ additionalProperties: SwiftStruct.Property?) throws {
        guard let props = additionalProperties else { return }

        let accessLevel = "public"
        let kind = props.isMutable ? "var" : "let"
        let type = try typeDeclaration(props.type)
        let typeCollection = "[String: \(type)]"
        let optionality = props.isOptional ? "?" : ""
        let defaultValue = try defaultValueDeclaration(props)
        let line = "\(accessLevel) \(kind) \(props.name): \(typeCollection)\(optionality)\(defaultValue ?? "")"

        writeEmptyLine()
        printComment(props.comment)
        writeLine(line)
    }

    private func printCodingKeys(for properties: [SwiftStruct.Property]) {
        writeEmptyLine()
        writeLine("enum CodingKeys: String, CodingKey {")
        indentRight()
        properties.forEach { property in
            writeLine("case \(property.name) = \"\(property.codingKey)\"")
        }
        indentLeft()
        writeLine("}")
    }

    private func printCodableMethods(for properties: [SwiftStruct.Property], additionalProperties: SwiftStruct.Property) throws {
        writeEmptyLine()
        writeLine("func encode(to encoder: Encoder) throws {")
        try indent {
            if properties.count > 0 {
                writeLine("var propsContainer = encoder.container(keyedBy: CodingKeys.self)")
                properties.forEach { property in
                    writeLine("try propsContainer.encode(\(property.name), forKey: .\(property.codingKey))")
                }
                writeEmptyLine()
            }

            writeLine("var addPropsContainer = encoder.container(keyedBy: DynamicCodingKey.self)")
            writeLine("try additionalProperties.forEach { key, value in")
            try indent {
                writeLine("try addPropsContainer.encode(value, forKey: DynamicCodingKey(key))")
            }
            writeLine("}")
        }
        writeLine("}")

        writeEmptyLine()
        writeLine("init(from decoder: Decoder) throws {")
        try indent {
            if properties.count > 0 {
                writeLine("var propsContainer = decoder.container(keyedBy: CodingKeys.self)")
                try properties.forEach { property in
                    let typeName = try typeDeclaration(property.type)
                    writeLine("\(property.name) = try propsContainer.decode(\(typeName).self, forKey: .\(property.codingKey))")
                }
                writeEmptyLine()
            }

            let typeName = try typeDeclaration(additionalProperties.type)
            writeLine("var addPropsContainer = decoder.container(keyedBy: DynamicCodingKey.self)")
            writeLine("let allKeys = addPropsContainer.allKeys")
            writeLine("try allKeys.forEach { key in")
            try indent {
                writeLine("let value = try addPropsContainer.decode(\(typeName).self, forKey: key)")
                writeLine("additionalProperties[key] = value")
            }
            writeLine("}")
        }
        writeLine("}")
    }

    private func printNestedTypes(in swiftStruct: SwiftStruct) throws {
        let nestedTypes = swiftStruct.properties.map { $0.type }
        try nestedTypes.forEach { type in
            let nestedStruct = (type as? SwiftStruct) ?? ((type as? SwiftArray)?.element as? SwiftStruct)
            let nestedEnum = (type as? SwiftEnum) ?? ((type as? SwiftArray)?.element as? SwiftEnum)

            if let nestedStruct = nestedStruct {
                writeEmptyLine()
                try printStruct(nestedStruct)
            } else if let nestedEnum = nestedEnum {
                writeEmptyLine()
                try printEnum(nestedEnum)
            }
        }
    }

    private func printEnum(_ enumeration: SwiftEnum) throws {
        let implementedProtocols = enumeration.conformance.map { $0.name }
        let conformance = implementedProtocols.isEmpty ? "" : ", \(implementedProtocols.joined(separator: ", "))"

        printComment(enumeration.comment)
        writeLine("public enum \(enumeration.name): String\(conformance) {")
        indentRight()
        enumeration.cases.forEach { `case` in
            writeLine("case \(`case`.label) = \"\(`case`.rawValue)\"")
        }
        indentLeft()
        writeLine("}")
    }

    // MARK: - Helpers

    private func typeDeclaration(_ type: SwiftType) throws -> String {
        switch type {
        case _ as SwiftPrimitive<Bool>:
            return "Bool"
        case _ as SwiftPrimitive<Double>:
            return "Double"
        case _ as SwiftPrimitive<Int>:
            return "Int"
        case _ as SwiftPrimitive<Int64>:
            return "Int64"
        case _ as SwiftPrimitive<String>:
            return "String"
        case let swiftArray as SwiftArray:
            return "[\(try typeDeclaration(swiftArray.element))]"
        case let swiftEnum as SwiftEnum:
            return swiftEnum.name
        case let swiftStruct as SwiftStruct:
            return swiftStruct.name
        case let swiftTypeReference as SwiftTypeReference:
            return swiftTypeReference.referencedTypeName
        default:
            throw Exception.unimplemented("Printing \(type) is not implemented.")
        }
    }

    private func defaultValueDeclaration(_ property: SwiftStruct.Property) throws -> String? {
        try property.defaultValue.ifNotNil { value in
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
    }
}
