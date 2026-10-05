/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
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

    func transform(jsonSchema: JSONSchema) throws -> JSONType {
        let schemaTitle = try (jsonSchema.title ?? jsonSchema.id)
            .unwrapOrThrow(
                .inconsistency("`JSONSchema` must define `title` or `$id`.")
            )

        return try transformSchemaToAnyType(jsonSchema, named: schemaTitle)
    }

    // MARK: - Transforming ambiguous types

    private func transformSchemaToAnyType(_ schema: JSONSchema, named name: String) throws -> JSONType {
        if schema.oneOf != nil || schema.anyOf != nil {
            return try transformSchemasToUnion(schema, named: name)
        }

        if schema.properties != nil {
            return try transformSchemaToObject(schema, named: name)
        }

        let schemaType: JSONSchema.SchemaType
        if let enumarations = schema.enum, schema.type == nil {
            schemaType = try enumarations.inferrSchemaType()
                .unwrapOrThrow(.inconsistency("Heteregenous enum is not supported: \(enumarations)."))
        } else if let constant = schema.const, schema.type == nil {
            // Infer type from const value when type is not explicitly declared (e.g. discriminator fields)
            switch constant.value {
            case .string: return JSONPrimitive.string
            case .integer: return JSONPrimitive.integer
            }
        } else {
            schemaType = try schema.type
                .unwrapOrThrow(.inconsistency("`JSONSchema` must define `type`: \(schema)."))
        }

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

    /// Transforms multiple non-homogeneous schemas (such as `oneOf: []`) into single `JSONUnionType`.
    private func transformSchemasToUnion(_ schema: JSONSchema, named name: String) throws -> JSONUnionType {
        let unionSchemas = try schema.oneOf ?? schema.anyOf
            .unwrapOrThrow(.inconsistency("`JSONSchema` must define `oneOf` or `anyOf`."))

        let discriminatorKey = findDiscriminatorKey(among: unionSchemas)
        return JSONUnionType(
            name: name,
            comment: schema.description,
            types: try unionSchemas.map { subschema in
                let variantName = resolveVariantName(subschema, discriminatorKey: discriminatorKey)
                return .init(
                    name: variantName,
                    type: try transformSchemaToAnyType(subschema, named: variantName ?? name)
                )
            }
        )
    }

    /// Returns the best variant name for `subschema` within a union, trying in priority order:
    /// 1. `title` (existing behaviour, used by all RUM event schemas)
    /// 2. A direct `const` value on the subschema (e.g. `{"type":"string","const":"all"}` → `"all"`)
    /// 3. The const value of a shared discriminator property across all object siblings
    /// 4. `$id` propagated from a `$ref` target via allOf merging (e.g. `"rum-sdk-config-ios"`)
    private func resolveVariantName(_ subschema: JSONSchema, discriminatorKey: String?) -> String? {
        if let title = subschema.title {
            return title
        }
        if let const = subschema.const {
            return const.value.description
        }
        if let key = discriminatorKey {
            return subschema.properties?[key]?.const?.value.description
        }
        if let id = subschema.id {
            return id
        }
        return nil
    }

    /// Returns a property key that appears in every object variant and carries a unique `const`
    /// value across all variants, or `nil` if no such key exists.
    private func findDiscriminatorKey(among schemas: [JSONSchema]) -> String? {
        guard schemas.allSatisfy({ $0.properties != nil }),
              let firstKeys = schemas.first?.properties?.keys else { return nil }

        return firstKeys.sorted().first { key in
            let consts = schemas.compactMap { $0.properties?[key]?.const?.value.description }
            return consts.count == schemas.count && Set(consts).count == schemas.count
        }
    }
}
