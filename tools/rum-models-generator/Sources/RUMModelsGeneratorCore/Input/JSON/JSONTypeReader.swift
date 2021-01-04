/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Reads `JSONObject` definition from `JSONSchema`.
internal class JSONTypeReader {
    struct Defaults {
        /// Properties are not required by default.
        static let isRequired = false
        /// Properties are read only by default.
        static let isReadOnly = true
    }

    func readJSONObject(from schema: JSONSchema) throws -> JSONObject {
        let schemaTitle = try schema.title.unwrapOrThrow(.inconsistency("Schema must define `title`."))
        let inferredType = try readAnyType(named: schemaTitle, from: schema)
        let objectType = inferredType as? JSONObject
        return try objectType
            .unwrapOrThrow(.illegal("Schema describes \(type(of: inferredType)) instead of `JSONObject`."))
    }

    // MARK: - Reading ambiguous types

    private func readAnyType(named name: String, from schema: JSONSchema) throws -> JSONType {
        let schemaType = try schema.type.unwrapOrThrow(.inconsistency("Schema must define `type`: \(schema)."))

        switch schemaType {
        case .object:
            return try readObject(from: schema, name: name)
        case .array:
            return try readArray(from: schema, name: name)
        case .boolean,
             .integer,
             .number:
            return try readPrimitive(from: schema)
        case .string:
            if schema.enum != nil {
                return try readEnumeration(from: schema, name: name)
            } else {
                return try readPrimitive(from: schema)
            }
        }
    }

    // MARK: - Reading concrete types

    private func readPrimitive(from schema: JSONSchema) throws -> JSONPrimitive {
        switch try schema.type.unwrapOrThrow(.inconsistency("Primitive definition must have `type`")) {
        case .boolean:
            return JSONPrimitive.bool
        case .integer:
            return JSONPrimitive.integer
        case .number:
            return JSONPrimitive.double
        case .string:
            return JSONPrimitive.string
        default:
            throw Exception.illegal("'\(schema.type?.rawValue ?? "(null)")' is not supported `PrimitiveType`.")
        }
    }

    private func readArray(from schema: JSONSchema, name: String) throws -> JSONArray {
        return JSONArray(
            element: try readAnyType(
                named: name,
                from: try schema.items.unwrapOrThrow(.inconsistency("`ArrayType` schema must define `items`."))
            )
        )
    }

    private func readEnumeration(from schema: JSONSchema, name: String) throws -> JSONEnumeration {
        return JSONEnumeration(
            name: name,
            comment: schema.description,
            values: try schema.enum.unwrapOrThrow(.inconsistency("`EnumerationType` schema must define `enum`."))
        )
    }

    private func readObject(from schema: JSONSchema, name: String) throws -> JSONObject {
        let propertiesByName = schema.properties ?? [:]
        var properties: [JSONObject.Property] = []

        try propertiesByName.forEach { propertyName, propertyDefinition in
            let property = JSONObject.Property(
                name: propertyName,
                comment: propertyDefinition.description,
                type: try readAnyType(named: propertyName, from: propertyDefinition),
                defaultVaule: propertyDefinition.const.flatMap { const in
                    switch const.value {
                    case .integer(let value): return .integer(value: value)
                    case .string(let value): return .string(value: value)
                    }
                },
                isRequired: schema.required?.contains(propertyName) ?? Defaults.isRequired,
                isReadOnly: propertyDefinition.readOnly ?? Defaults.isReadOnly
            )

            properties.append(property)
        }

        return JSONObject(name: name, comment: schema.description, properties: properties)
    }
}
