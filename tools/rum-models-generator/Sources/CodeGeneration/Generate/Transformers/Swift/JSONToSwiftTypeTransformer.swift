/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Transforms `JSONObject` schema into `SwiftStruct` schema.
internal class JSONToSwiftTypeTransformer {
    func transform(jsonType: JSONType) throws -> [SwiftStruct] {
        return try transform(rootJSONType: jsonType)
    }

    // MARK: - Transforming root types

    func transform(rootJSONType: JSONType) throws -> [SwiftStruct] {
        switch rootJSONType {
        case let jsonObject as JSONObject:
            return [try transform(rootJSONObject: jsonObject)]
        case let jsonUnion as JSONUnionType:
            return try transform(rootJSONUnion: jsonUnion)
        default:
            throw Exception.unimplemented("Transforming root object of type `\(type(of: rootJSONType))` is not supported.")
        }
    }

    private func transform(rootJSONObject: JSONObject) throws -> SwiftStruct {
        guard rootJSONObject.additionalProperties == nil else {
            throw Exception.unimplemented("Transforming root `JSONObject` with `additionalProperties` is not supported.")
        }
        var `struct` = try transformJSONObjectToStruct(rootJSONObject)
        `struct` = resolveTransitiveMutableProperties(in: `struct`)
        return `struct`
    }

    private func transform(rootJSONUnion: JSONUnionType) throws -> [SwiftStruct] {
        let numberOfTypes = rootJSONUnion.types.count
        let jsonObjects = rootJSONUnion.types.compactMap { $0.type as? JSONObject }
        let jsonUnion = rootJSONUnion.types.compactMap { $0.type as? JSONUnionType }

        guard (jsonObjects.count + jsonUnion.count) == numberOfTypes else {
            let mixedTypes = rootJSONUnion.types.map { "\(type(of: $0))" }
            throw Exception.unimplemented("Transforming root `JSONOneOfs` with mixed `oneOf` types is not supported (mixed types: \(mixedTypes)).")
        }

        let transformedJSONOneOfs = try jsonUnion.flatMap { try transform(rootJSONUnion: $0) }
        let transformedJSONObjects = try jsonObjects.map { try transform(rootJSONObject: $0) }

        return transformedJSONOneOfs + transformedJSONObjects
    }

    // MARK: - Transforming ambiguous types

    private func transformJSONToAnyType(_ json: JSONType) throws -> SwiftType {
        switch json {
        case let jsonPrimitive as JSONPrimitive:
            return try transformJSONtoPrimitive(jsonPrimitive)
        case let jsonArray as JSONArray:
            return try transformJSONToArray(jsonArray)
        case let jsonEnumeration as JSONEnumeration:
            return transformJSONToEnum(jsonEnumeration)
        case let jsonObject as JSONObject:
            return try transformJSONObject(jsonObject)
        case let jsonUnion as JSONUnionType:
            return try transformJSONUnion(jsonUnion)
        default:
            throw Exception.unimplemented("Transforming `\(type(of: json))` into `SwiftType` is not supported.")
        }
    }

    // MARK: - Transforming concrete types

    private func transformJSONtoPrimitive(_ jsonPrimitive: JSONPrimitive) throws -> SwiftPrimitiveType {
        switch jsonPrimitive {
        case .bool: return SwiftPrimitive<Bool>()
        case .double: return SwiftPrimitive<Double>()
        case .integer: return SwiftPrimitive<Int>()
        case .string: return SwiftPrimitive<String>()
        case .any: throw Exception.illegal("Untyped JSON schema (`.any`) cannot be transformed to `SwiftPrimitiveType`.")
        }
    }

    private func transformJSONToArray(_ jsonArray: JSONArray) throws -> SwiftArray {
        return SwiftArray(element: try transformJSONToAnyType(jsonArray.element))
    }

    private func transformJSONToEnum(_ jsonEnumeration: JSONEnumeration) -> SwiftEnum {
        return SwiftEnum(
            name: jsonEnumeration.name,
            comment: jsonEnumeration.comment,
            cases: jsonEnumeration.values.map { value in
                switch value {
                case .string(let value):
                    // In Swift, enum case names cannot start with digits. In such situation prefix the
                    // case with the name of enumeration so it is transformed into valid `SwiftEnum.Case`.
                    var labelValue = value
                    if let first = value.first?.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
                        labelValue = "\(jsonEnumeration.name)\(value)"
                    }

                    return SwiftEnum.Case(label: labelValue, rawValue: .string(value: value))
                case .integer(let value):
                    // In Swift, enum case names cannot start with digits, so prefix the case with the name
                    // of enumeration so it is transformed into valid `SwiftEnum.Case`.
                    return SwiftEnum.Case(label: "\(jsonEnumeration.name)\(value)", rawValue: .integer(value: value))
                }
            },
            conformance: []
        )
    }

    private func transformJSONObject(_ jsonObject: JSONObject) throws -> SwiftType {
        if let additionalProperties = jsonObject.additionalProperties {
            if additionalProperties.type == .any {
                // RUMM-1401: if schema declares `additionalProperties: true` or `additionalProperties: {type: object, ...}`
                // we model it as a `struct` with nested `<public|public internal(set)><var> <structName>Info: [String: Codable]`
                // dictionary. In generated encoding code, this dictionary is erased but its keys and values are used as dynamic
                // properties encoded in JSON.
                let additionalPropertyName = jsonObject.name + "Info"
                // RUMM-1420: we noticed that `additionalProperties` is used for custom user attributes which need to be
                // sanitized by the SDK, hence it's very practical for us to generate `.mutableInternally` modifier for those.
                let mutability: SwiftStruct.Property.Mutability = additionalProperties.isReadOnly ? .mutableInternally : .mutable
                var `struct` = try transformJSONObjectToStruct(jsonObject)
                `struct`.properties.append(
                    SwiftStruct.Property(
                        name: additionalPropertyName,
                        comment: additionalProperties.comment,
                        type: SwiftDictionary(
                            value: SwiftEncodable()
                        ),
                        isOptional: false,
                        mutability: mutability,
                        defaultValue: nil,
                        codingKey: .dynamic
                    )
                )
                return `struct`
            } else {
                // RUMM-1401: if schema declares `additionalProperties: {type: string | bool | integer | double, ...}}`
                // we model it as dictionary property.
                return SwiftDictionary(
                    value: try transformJSONtoPrimitive(additionalProperties.type)
                )
            }
        } else {
            return try transformJSONObjectToStruct(jsonObject)
        }
    }

    private func transformJSONObjectToStruct(_ jsonObject: JSONObject) throws -> SwiftStruct {
        /// Reads Struct properties.
        func readProperties(from objectProperties: [JSONObject.Property]) throws -> [SwiftStruct.Property] {
            /// Reads Struct property default value.
            func readDefaultValue(for objectProperty: JSONObject.Property) throws -> SwiftPropertyDefaultValue? {
                return objectProperty.defaultValue.ifNotNil { value in
                    switch value {
                    case .integer(let intValue):
                        return intValue
                    case .string(let stringValue):
                        if objectProperty.type is JSONEnumeration {
                            return SwiftEnum.Case(label: stringValue, rawValue: .string(value: stringValue))
                        } else {
                            return stringValue
                        }
                    }
                }
            }

            return try objectProperties.map { jsonProperty in
                let mutability: SwiftStruct.Property.Mutability = jsonProperty.isReadOnly ? .immutable : .mutable
                return SwiftStruct.Property(
                    name: jsonProperty.name,
                    comment: jsonProperty.comment,
                    type: try transformJSONToAnyType(jsonProperty.type),
                    isOptional: !jsonProperty.isRequired,
                    mutability: mutability,
                    defaultValue: try readDefaultValue(for: jsonProperty),
                    codingKey: .static(value: jsonProperty.name)
                )
            }
        }

        return SwiftStruct(
            name: jsonObject.name,
            comment: jsonObject.comment,
            properties: try readProperties(from: jsonObject.properties),
            conformance: []
        )
    }

    /// The `oneOf` and `anyOf` schemas appearing in nested (not root) context gets transformed into Swift enum
    /// with associated values for representing union types. Each `case` represents a single sub-suchema from
    /// `oneOf` or `anyOf` array.
    ///
    /// Following default and fallback for determining `case` names (labels) are implemented:
    /// - If **all**  sub-schemas define their `title` **and** all titles are unique, enum cases will be
    /// named by sub-schema titles.
    /// - Otherwise, if **all** sub-schemas represent different `types`, enum cases will be named by
    /// the name of sub-schema `type`.
    /// - If none of above is met, an incompatibility error will be thrown.
    private func transformJSONUnion(_ jsonUnion: JSONUnionType) throws -> SwiftAssociatedTypeEnum {
        // Determine case labels:
        let caseLabels: [String]

        // Build names from sub-schemas `title` (given by `oneOf/anyOf.name`):
        let labelsFromNames = jsonUnion.types.compactMap { $0.name }
        // Check if labels from names are present and if all are unique:
        let areLabelsFromNamesUnique = Set(labelsFromNames).count == jsonUnion.types.count

        if areLabelsFromNamesUnique {
            caseLabels = labelsFromNames
        } else {
            // Fallback to inferring names from sub-schemas `type`:
            func labelNameFromType(of jsonType: JSONType) throws -> String {
                switch jsonType {
                case let jsonPrimitive as JSONPrimitive:
                    return jsonPrimitive.rawValue // e.g. `bool` or `double`
                case let jsonArray as JSONArray:
                    return try labelNameFromType(of: jsonArray.element) + "sArray" // e.g. `doublesArray`, `foosArray`
                default:
                    throw Exception.unimplemented("Building `SwiftAssociatedTypeEnum` case label for \(type(of: jsonType)) is not supported")
                }
            }

            caseLabels = try jsonUnion.types.map { try labelNameFromType(of: $0.type) }
        }

        return SwiftAssociatedTypeEnum(
            name: jsonUnion.name,
            comment: jsonUnion.comment,
            cases: try zip(jsonUnion.types, caseLabels).map { schema, caseLabel in
                return SwiftAssociatedTypeEnum.Case(
                    label: caseLabel,
                    associatedType: try transformJSONToAnyType(schema.type)
                )
            },
            conformance: []
        )
    }

    // MARK: - Resolving transitive mutable properties

    /// Looks recursively into given `struct` and changes mutability
    /// signatures in properties referencing structs with mutable properties.
    ///
    /// For example, receiving such structure as input:
    ///
    ///         struct Foo {
    ///             struct Bar {
    ///                 let bizz: String
    ///                 var buzz: String // ⚠️ this can't be mutated as `bar` is immutable
    ///             }
    ///             let bar: Bar
    ///         }
    ///
    /// it transforms the `bar` property mutability signature from `let` to `var` to allow modification of `buzz` property:
    ///
    ///         struct Foo {
    ///             struct Bar {
    ///                 let bizz: String
    ///                 var buzz: String
    ///             }
    ///             var bar: Bar // 💫 fix, now `bar.buzz` can be mutated
    ///         }
    ///
    private func resolveTransitiveMutableProperties(in `struct`: SwiftStruct) -> SwiftStruct {
        var `struct` = `struct`

        `struct`.properties = `struct`.properties.map { property in
            var property = property
            property.mutability = transitiveMutability(of: property)

            if let nestedStruct = property.type as? SwiftStruct {
                property.type = resolveTransitiveMutableProperties(in: nestedStruct)
            }

            return property
        }

        return `struct`
    }

    /// Returns the mutability level of the given `SwiftStruct.Property` by checking the mutability levels of its element or nested types.
    ///
    /// This stands for: _if the child is mutable, its parent must be mutable too_;
    /// e.g.: in `foo.bar.property = 2` expression, not only `property` must be mutable, but also its parent `bar` accessor.
    private func transitiveMutability(of property: SwiftStruct.Property) -> SwiftStruct.Property.Mutability {
        resolve(parentMutability: property.mutability, childMutability: transitiveMutableProperty(of: property.type))
    }

    /// Returns the mutability level of the given `SwiftType` by checking the mutability levels of its element or nested types.
    ///
    /// This stands for: _if the child is mutable, its parent must be mutable too_;
    /// e.g.: in `foo.bar.property = 2` expression, not only `property` must be mutable, but also its parent `bar` accessor.
    private func transitiveMutableProperty(of type: SwiftType) -> SwiftStruct.Property.Mutability {
        switch type {
        case let array as SwiftArray:
            return transitiveMutableProperty(of: array.element)
        case let `struct` as SwiftStruct:
            // Returns the highest level of mutability of the struct's inner properties
            // .immutable < .mutableInternally < .mutable
            return `struct`.properties.reduce(.immutable) {
                self.resolve(parentMutability: $0, childMutability: transitiveMutability(of: $1))
            }
        default:
            return .immutable
        }
    }

    /// Returns new `Mutability` for parent type given its child `Mutability`.
    ///
    /// This stands for: _if the child is mutable, its parent must be mutable too_;
    /// e.g.: in `foo.bar.property = 2` expression, not only `property` must be mutable, but also its parent `bar` accessor.
    private func resolve(
        parentMutability: SwiftStruct.Property.Mutability,
        childMutability: SwiftStruct.Property.Mutability
    ) -> SwiftStruct.Property.Mutability {
        return parentMutability.rawValue > childMutability.rawValue ? parentMutability : childMutability
    }
}
