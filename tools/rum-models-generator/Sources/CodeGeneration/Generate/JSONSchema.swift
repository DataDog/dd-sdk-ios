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
        case defs = "$defs"
        case definitions = "definitions"
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

    struct SchemaConstant: Decodable, Equatable {
        enum Value: Equatable, CustomStringConvertible {
            case integer(value: Int)
            case string(value: String)

            var description: String {
                switch self {
                case .integer(let value):
                    return "\(value)"
                case .string(let value):
                    return value
                }
            }
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

        init(value: Value) {
            self.value = value
        }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.properties = try container.decodeIfPresent([String: JSONSchema].self, forKey: .properties)
        self.required = try container.decodeIfPresent([String].self, forKey: .required)
        self.`enum` = try container.decodeIfPresent([EnumValue].self, forKey: .enum)
        self.const = try container.decodeIfPresent(SchemaConstant.self, forKey: .const)
        self.items = try container.decodeIfPresent(JSONSchema.self, forKey: .items)
        self.readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly)
        self.ref = try container.decodeIfPresent(String.self, forKey: .ref)
        self.defs = try container.decodeIfPresent([String: JSONSchema].self, forKey: .defs)
        self.definitions = try container.decodeIfPresent([String: JSONSchema].self, forKey: .definitions)
        self.allOf = try container.decodeIfPresent([JSONSchema].self, forKey: .allOf)
        self.oneOf = try container.decodeIfPresent([JSONSchema].self, forKey: .oneOf)
        self.anyOf = try container.decodeIfPresent([JSONSchema].self, forKey: .anyOf)

        self.additionalProperties = try Self.decodeAdditionalProperties(from: container)
        // RUMM-2266: infer `.object` when `properties` exist but `type` is absent.
        self.type = try Self.decodeType(from: container) ?? (properties != nil ? .object : nil)
    }

    /// Decodes `additionalProperties`, which JSON Schema allows as `true`, `false`, or a schema object.
    /// `false` → `nil` (nothing to generate); `true` → unconstrained object schema.
    private static func decodeAdditionalProperties(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> JSONSchema? {
        if let bool = try? container.decode(Bool.self, forKey: .additionalProperties) {
            guard bool else {
                return nil
            }
            let schema = JSONSchema()
            schema.type = .object
            return schema
        }
        return try container.decodeIfPresent(JSONSchema.self, forKey: .additionalProperties)
    }

    /// Decodes `type`, which JSON Schema allows as a single string or an array of strings.
    /// When it's an array (e.g. `["array", "null"]`), returns the first non-`null` entry.
    private static func decodeType(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> SchemaType? {
        if let single = try? container.decodeIfPresent(SchemaType.self, forKey: .type) {
            return single
        }
        if let array = try? container.decode([String].self, forKey: .type) {
            return array.first(where: { $0 != "null" }).flatMap(SchemaType.init(rawValue:))
        }
        return nil
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

    /// In-document schema definitions.
    /// https://json-schema.org/draft/2019-09/json-schema-core.html#defs
    private(set) var defs: [String: JSONSchema]?

    /// In-document schema definitions (draft-07 `definitions` keyword, equivalent to `$defs`).
    private(set) var definitions: [String: JSONSchema]?

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

    /// Navigates a JSON Pointer path from a root schema, returning `nil` for any unsupported step.
    private static func navigate(_ path: ArraySlice<String>, in schema: JSONSchema) -> JSONSchema? {
        guard let key = path.first else {
            return schema
        }
        switch key {
        case "$defs":
            return path.dropFirst().first.flatMap { schema.defs?[$0] }.flatMap { navigate(path.dropFirst(2), in: $0) }
        case "definitions":
            return path.dropFirst().first.flatMap { schema.definitions?[$0] }.flatMap { navigate(path.dropFirst(2), in: $0) }
        case "properties":
            return path.dropFirst().first.flatMap { schema.properties?[$0] }.flatMap { navigate(path.dropFirst(2), in: $0) }
        case "items":
            return schema.items.flatMap { navigate(path.dropFirst(), in: $0) }
        default:
            return nil
        }
    }

    /// Resolves `$ref` recursively.
    ///
    /// All sub-schemas with `$ref`, including `self` will be resolved.
    /// Only `allOf` references will be merged with `self` while `oneOf`
    /// are kept as orphan objects
    ///
    /// - Parameters:
    ///   - directory: The directory in which to look for referred schemas.
    ///   - reader: The schema file reader.
    ///   - root: The document root schema, used to resolve in-document `#/...` refs.
    func resolveReferences(in directory: URL, using reader: JSONSchemaReader, root: JSONSchema? = nil) throws {
        let effectiveRoot = root ?? self

        // resolve `$defs` / `definitions` entries first so they're ready as resolution targets
        try self.defs?.values.forEach {
            try $0.resolveReferences(in: directory, using: reader, root: effectiveRoot)
        }
        try self.definitions?.values.forEach {
            try $0.resolveReferences(in: directory, using: reader, root: effectiveRoot)
        }

        // resolve `properties.$ref`
        try properties?.map(\.value).forEach {
            try $0.resolveReferences(in: directory, using: reader, root: effectiveRoot)
        }

        // resolve `items.$ref`
        try items.map {
            try $0.resolveReferences(in: directory, using: reader, root: effectiveRoot)
        }

        // resolve `oneOf[].$ref`
        // `oneOf` schemas are kept as orphans
        try oneOf?.forEach {
            try $0.resolveReferences(in: directory, using: reader, root: effectiveRoot)
        }

        // resolve `allOf[].$ref`
        // merge `allOf` schemas with `self`
        try allOf?.forEach {
            try $0.resolveReferences(in: directory, using: reader, root: effectiveRoot)
            merge(with: $0)
        }

        // resolve `anyOf[].$ref`
        try anyOf?.forEach {
            try $0.resolveReferences(in: directory, using: reader, root: effectiveRoot)
        }

        // resolve `$ref`
        // Refs follow the JSON Reference format: `[file]#[/json/pointer]`
        // Both parts are optional: `#/foo` (in-document), `other.json` (whole file), `other.json#/foo` (cross-file).
        try ref.map { ref in
            let range = ref.range(of: "#")
            let file = range.map { String(ref[ref.startIndex..<$0.lowerBound]) } ?? ref
            let fragment = range.map { String(ref[$0.upperBound...]) }

            let root = file.isEmpty
                ? effectiveRoot
                : try reader.read(directory.appendingPathComponent(file))

            if let fragment, !fragment.isEmpty {
                let parts = fragment.split(separator: "/").map(String.init)
                guard let resolved = Self.navigate(parts[...], in: root) else {
                    throw Exception.unimplemented("Unsupported $ref path: \(ref)")
                }
                merge(with: resolved)
            } else {
                merge(with: root)
            }
        }

        oneOf = oneOf?.compactMap { obj in
            if obj.title == "TelemetryCommonFeaturesUsage" || obj.title == "TelemetryMobileFeaturesUsage" {
                // transform telemetry spec to mobile compatible
                guard let oneOf = obj.oneOf else {
                    return obj
                }

                // promote `feature` property to `title` if `title` is missing
                for one in oneOf {
                    if one.title == nil {
                        one.title = one.properties?["feature"]?.const?.value.description
                    }
                }

                return obj
            } else if obj.title == "TelemetryBrowserFeaturesUsage" {
                // skip browser telemetry
                return nil
            } else {
                return obj
            }
        }
    }

    // MARK: - Schemas Merging

    /// Merges all attributes of `otherSchema` into this schema.
    private func merge(with otherSchema: JSONSchema?) {
        guard let otherSchema = otherSchema else {
            return
        }

        // id and title can be inferred from the merged schema
        self.id = self.id ?? otherSchema.id
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
