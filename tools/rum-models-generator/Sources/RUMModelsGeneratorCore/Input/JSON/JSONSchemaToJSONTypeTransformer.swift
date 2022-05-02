/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Transforms ambiguous `JSONSchema` into type-safe `JSONObject` schema.
internal class JSONSchemaToJSONTypeTransformer {
    struct Defaults {
        /// Properties are not required by default.
        static let isRequired = false
        /// Properties are read only by default.
        static let isReadOnly = true
    }

    func transform(jsonSchemas: [JSONSchema]) throws -> [JSONObject] {
        return try jsonSchemas.map { try transform(jsonSchema: $0) }
    }

    private func transform(jsonSchema: JSONSchema) throws -> JSONObject {
        let schemaTitle = try jsonSchema.title
            .unwrapOrThrow(.inconsistency("`JSONSchema` must define `title`."))
        let inferredType = try transformSchemaToAnyType(jsonSchema, named: schemaTitle)
        let objectType = try (inferredType as? JSONObject)
            .unwrapOrThrow(
                .illegal("`JSONSchema` describes \(type(of: inferredType)) instead of `JSONObject`.")
            )
        return objectType
    }

    // MARK: - Transforming ambiguous types

    private func transformSchemaToAnyType(_ schema: JSONSchema, named name: String) throws -> JSONType {
        // RUMM-2022: Pick first schema of OneOf to workaround change introduced in
        // https://github.com/DataDog/rum-events-format/pull/57
        //
        // Supporting multiple types for single property need to be addressed
        if let oneOf = schema.oneOf?.first {
            return try transformSchemaToAnyType(oneOf, named: name)
        }

        let schemaType = try schema.type
            .unwrapOrThrow(.inconsistency("`JSONSchema` must define `type`: \(schema)."))

        switch schemaType {
        case .object:
            return try transformSchemaToObject(schema, named: name)
        case .array:
            return try transformSchemaToArray(schema, named: name)
        case .boolean, .integer, .number:
            if schema.enum != nil {
                return try transformSchemaToEnumeration(schema, named: name)
            } else {
                return try transformSchemaToPrimitive(schema)
            }
        case .string:
            if schema.enum != nil {
                return try transformSchemaToEnumeration(schema, named: name)
            } else {
                return try transformSchemaToPrimitive(schema)
            }
        }
    }

    // MARK: - Transforming concrete types

    private func transformSchemaToPrimitive(_ schema: JSONSchema) throws -> JSONPrimitive {
        switch try schema.type.unwrapOrThrow(.inconsistency("`JSONPrimitive` must have `type`")) {
        case .boolean:
            return JSONPrimitive.bool
        case .integer:
            return JSONPrimitive.integer
        case .number:
            return JSONPrimitive.double
        case .string:
            return JSONPrimitive.string
        case .object:
            return JSONPrimitive.any
        default:
            throw Exception.illegal(
                "'\(schema.type?.rawValue ?? "(null)")' is not supported `JSONPrimitive`."
            )
        }
    }

    private func transformSchemaToArray(_ schema: JSONSchema, named name: String) throws -> JSONArray {
        return JSONArray(
            element: try transformSchemaToAnyType(
                try schema.items
                    .unwrapOrThrow(.inconsistency("`JSONArray` schema must define `items`.")),
                named: name
            )
        )
    }

    private func transformSchemaToEnumeration(_ schema: JSONSchema, named name: String) throws -> JSONEnumeration {
        return JSONEnumeration(
            name: name,
            comment: schema.description,
            values: try schema.enum
                .unwrapOrThrow(.inconsistency("`JSONEnumeration` schema must define `enum`."))
                .map { schemaValue in
                    switch schemaValue {
                    case .string(let value): return .string(value: value)
                    case .integer(let value): return .integer(value: value)
                    }
                }
        )
    }

    private func transformSchemaToObject(_ schema: JSONSchema, named name: String) throws -> JSONObject {
        let propertiesByName = schema.properties ?? [:]
        var properties: [JSONObject.Property] = []

        try propertiesByName.forEach { propertyName, propertySchema in
            let property = JSONObject.Property(
                name: propertyName,
                comment: propertySchema.description,
                type: try transformSchemaToAnyType(propertySchema, named: propertyName),
                defaultValue: propertySchema.const.flatMap { const in
                    switch const.value {
                    case .integer(let value): return .integer(value: value)
                    case .string(let value): return .string(value: value)
                    }
                },
                isRequired: schema.required?.contains(propertyName) ?? Defaults.isRequired,
                isReadOnly: propertySchema.readOnly ?? Defaults.isReadOnly
            )
            properties.append(property)
        }

        let additionalProperties: JSONObject.AdditionalProperties?
        if let additionalPropertiesSchema = schema.additionalProperties {
            let type = try transformSchemaToPrimitive(additionalPropertiesSchema)
            additionalProperties = JSONObject.AdditionalProperties(
                comment: additionalPropertiesSchema.description,
                type: type,
                isReadOnly: additionalPropertiesSchema.readOnly ?? Defaults.isReadOnly
            )
        } else {
            additionalProperties = nil
        }

        return JSONObject(
            name: name,
            comment: schema.description,
            properties: properties,
            additionalProperties: additionalProperties
        )
    }
}
