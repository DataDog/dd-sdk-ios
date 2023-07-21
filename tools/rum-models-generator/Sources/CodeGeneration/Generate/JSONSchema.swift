/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Broad description of the JSON schema. It is agnostic and independent of any programming language.
///
/// Based on: https://json-schema.org/draft/2019-09/json-schema-core.html it implements
/// only concepts used in the `rum-events-format` schemas.
internal class JSONSchema: Decodable {
    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case title = "title"
        case description = "description"
        case properties = "properties"
        case additionalProperties = "additionalProperties"
        case required = "required"
        case type = "type"
        case `enum` = "enum"
        case const = "const"
        case items = "items"
        case readOnly = "readOnly"
        case ref = "$ref"
        case oneOf = "oneOf"
        case anyOf = "anyOf"
        case allOf = "allOf"
    }

    enum SchemaType: String, Decodable {
        case boolean
        case object
        case array
        case number
        case string
        case integer
    }

    struct SchemaConstant: Decodable {
        enum Value: Equatable {
            case integer(value: Int)
            case string(value: String)
        }

        let value: Value

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let int = try? container.decode(Int.self) {
                value = .integer(value: int)
            } else if let string = try? container.decode(String.self) {
                value = .string(value: string)
            } else {
                let prettyKeyPath = container.codingPath.map({ $0.stringValue }).joined(separator: " → ")
                throw Exception.unimplemented(
                    "The value on key path: `\(prettyKeyPath)` is not supported by `JSONSchemaDefinition.ConstantValue`."
                )
            }
        }
    }

    required init(from decoder: Decoder) throws {
        do {
            // First try decoding with keyed container
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try keyedContainer.decodeIfPresent(String.self, forKey: .id)
            self.title = try keyedContainer.decodeIfPresent(String.self, forKey: .title)
            self.description = try keyedContainer.decodeIfPresent(String.self, forKey: .description)
            self.properties = try keyedContainer.decodeIfPresent([String: JSONSchema].self, forKey: .properties)
            self.additionalProperties = try keyedContainer.decodeIfPresent(JSONSchema.self, forKey: .additionalProperties)
            self.required = try keyedContainer.decodeIfPresent([String].self, forKey: .required)
            self.type = try keyedContainer.decodeIfPresent(SchemaType.self, forKey: .type)
            self.enum = try keyedContainer.decodeIfPresent([EnumValue].self, forKey: .enum)
            self.const = try keyedContainer.decodeIfPresent(SchemaConstant.self, forKey: .const)
            self.items = try keyedContainer.decodeIfPresent(JSONSchema.self, forKey: .items)
            self.readOnly = try keyedContainer.decodeIfPresent(Bool.self, forKey: .readOnly)
            self.ref = try keyedContainer.decodeIfPresent(String.self, forKey: .ref)
            self.allOf = try keyedContainer.decodeIfPresent([JSONSchema].self, forKey: .allOf)
            self.oneOf = try keyedContainer.decodeIfPresent([JSONSchema].self, forKey: .oneOf)
            self.anyOf = try keyedContainer.decodeIfPresent([JSONSchema].self, forKey: .anyOf)

            // RUMM-2266 Patch:
            // If schema doesn't define `type`, but defines `properties`, it is safe to assume
            // that its `.object` schema:
            if self.type == nil && self.properties != nil {
                self.type = .object
            }
        } catch let keyedContainerError as DecodingError {
            // If data in this `decoder` cannot be represented as keyed container, perhaps it encodes
            // a single value. Check known schema values:
            do {
                if decoder.codingPath.last as? JSONSchema.CodingKeys == .additionalProperties {
                    // Handle `additionalProperties: true | false`
                    let singleValueContainer = try decoder.singleValueContainer()
                    let hasAdditionalProperties = try singleValueContainer.decode(Bool.self)

                    if hasAdditionalProperties {
                        self.type = .object
                    } else {
                        throw Exception.moreContext(
                            "Decoding `additionalProperties: false` is not supported in `JSONSchema.init(from:)`.",
                            for: keyedContainerError
                        )
                    }
                } else {
                    throw Exception.moreContext(
                        "Decoding \(decoder.codingPath) is not supported in `JSONSchema.init(from:)`.",
                        for: keyedContainerError
                    )
                }
            } catch let singleValueContainerError {
                throw Exception.moreContext(
                    "Unhandled parsing exception in `JSONSchema.init(from:)`.",
                    for: singleValueContainerError
                )
            }
        }
    }

    init() {}

    // MARK: - Schema attributes

    enum EnumValue: Decodable, Equatable {
        case string(String)
        case integer(Int)

        init(from decoder: Decoder) throws {
            let singleValueContainer = try decoder.singleValueContainer()
            if let string = try? singleValueContainer.decode(String.self) {
                self = .string(string)
            } else if let integer = try? singleValueContainer.decode(Int.self) {
                self = .integer(integer)
            } else {
                throw Exception.unimplemented("Trying to decode `EnumValue` but its none of supported values.")
            }
        }
    }

    private(set) var id: String?
    private(set) var title: String?
    private(set) var description: String?
    private(set) var properties: [String: JSONSchema]?
    private(set) var additionalProperties: JSONSchema?
    private(set) var required: [String]?
    private(set) var type: SchemaType?
    private(set) var `enum`: [EnumValue]?
    private(set) var const: SchemaConstant?
    private(set) var items: JSONSchema?
    private(set) var readOnly: Bool?

    /// Reference to another schema.
    /// https://json-schema.org/draft/2019-09/json-schema-core.html#ref
    private var ref: String?

    /// Subschemas to be resolved.
    /// https://json-schema.org/draft/2019-09/json-schema-core.html#rfc.section.9.2.1.1
    private(set) var allOf: [JSONSchema]?

    /// Subschemas to be resolved.
    /// https://json-schema.org/draft/2019-09/json-schema-core.html#rfc.section.9.2.1.2
    private(set) var anyOf: [JSONSchema]?

    /// Subschemas to be resolved.
    /// https://json-schema.org/draft/2019-09/json-schema-core.html#rfc.section.9.2.1.3
    private(set) var oneOf: [JSONSchema]?

    // MARK: - Resolving Schema References

    /// Resolves `$ref` recursively.
    ///
    /// All sub-schemas with `$ref`, including `self` will be resolved.
    /// Only `allOf` references will be merged with `self` while `oneOf`
    /// are kept as orphan objects
    ///
    /// - Parameters:
    ///   - directory: The directory in which to look for referred schemas.
    ///   - reader: The schema file reader.
    func resolveReferences(in directory: URL, using reader: JSONSchemaReader) throws {
        // resolve `properties.$ref`
        try properties?.map(\.value).forEach {
            try $0.resolveReferences(in: directory, using: reader)
        }

        // resolve `items.$ref`
        try items.map {
            try $0.resolveReferences(in: directory, using: reader)
        }

        // resolve `oneOf[].$ref`
        // `oneOf` schemas are kept as orphans
        try oneOf?.forEach {
            try $0.resolveReferences(in: directory, using: reader)
        }

        // resolve `allOf[].$ref`
        // merge `allOf` schemas with `self`
        try allOf?.forEach {
            try $0.resolveReferences(in: directory, using: reader)
            merge(with: $0)
        }

        // resolve `$ref`
        try ref.map { ref in
            let url = directory.appendingPathComponent(ref)
            let schema = try reader.read(url)
            merge(with: schema)
        }
    }

    // MARK: - Schemas Merging

    /// Merges all attributes of `otherSchema` into this schema.
    private func merge(with otherSchema: JSONSchema?) {
        guard let otherSchema = otherSchema else {
            return
        }

        // Title can be overwritten
        self.title = self.title ?? otherSchema.title

        // Description can be overwritten
        self.description = self.description ?? otherSchema.description

        // Type can be inferred
        self.type = self.type ?? otherSchema.type

        // Properties are accumulated and if both schemas have a property with the same name, property
        // schemas are merged.
        if let selfProperties = self.properties, let otherProperties = otherSchema.properties {
            self.properties = selfProperties.merging(otherProperties) { selfProperty, otherProperty in
                selfProperty.merge(with: otherProperty)
                return selfProperty
            }
        } else {
            self.properties = self.properties ?? otherSchema.properties
        }

        self.additionalProperties = self.additionalProperties ?? otherSchema.additionalProperties

        // Required properties are accumulated.
        if let selfRequired = self.required, let otherRequired = otherSchema.required {
            self.required = selfRequired + otherRequired
        } else {
            self.required = self.required ?? otherSchema.required
        }

        // Enumeration values are accumulated.
        if let selfEnum = self.enum, let otherEnum = otherSchema.enum {
            self.enum = selfEnum + otherEnum
        } else {
            self.enum = self.enum ?? otherSchema.enum
        }

        // Constant value can be overwritten.
        self.const = self.const ?? otherSchema.const

        // If both schemas have Items, their schemas are merged.
        // Otherwise, any non-nil Items schema is taken.
        if let selfItems = self.items, let otherItems = otherSchema.items {
            selfItems.merge(with: otherItems)
        } else {
            self.items = self.items ?? otherSchema.items
        }

        // If both schemas define read-only value, the most strict is taken.
        if let selfReadOnly = self.readOnly, let otherReadOnly = otherSchema.readOnly {
            self.readOnly = selfReadOnly || otherReadOnly
        } else {
            self.readOnly = self.readOnly ?? otherSchema.readOnly
        }

        // Accumulate `oneOf` schemas
        if let selfOneOf = oneOf, let otherOneOf = otherSchema.oneOf {
            self.oneOf = selfOneOf + otherOneOf
        } else if let otherOneOf = otherSchema.oneOf {
            self.oneOf = otherOneOf
        }

        // Accumulate `anyOf` schemas
        if let selfAnyOf = anyOf, let otherAnyOf = otherSchema.anyOf {
            self.anyOf = selfAnyOf + otherAnyOf
        } else if let otherAnyOf = otherSchema.anyOf {
            self.anyOf = otherAnyOf
        }
    }
}

extension Array where Element == JSONSchema.EnumValue {
    func inferrSchemaType() -> JSONSchema.SchemaType? {
        let hasOnlyStrings = allSatisfy { element in
            if case .string = element {
                return true
            }
            return false
        }
        if hasOnlyStrings {
            return .string
        }

        let hasOnlyIntegers = allSatisfy { element in
            if case .integer = element {
                return true
            }
            return false
        }
        if hasOnlyIntegers {
            return .number
        }

        return nil
    }
}
