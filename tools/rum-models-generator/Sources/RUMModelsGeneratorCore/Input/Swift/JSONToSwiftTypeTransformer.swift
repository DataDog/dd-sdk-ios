/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Transforms `JSONObject` schema into `SwiftStruct` schema.
internal class JSONToSwiftTypeTransformer {
    func transform(jsonObjects: [JSONObject]) throws -> [SwiftStruct] {
        return try jsonObjects.map { try transform(jsonObject: $0) }
    }

    private func transform(jsonObject: JSONObject) throws -> SwiftStruct {
        if jsonObject.additionalProperties != nil {
            throw Exception.unimplemented("Transforming root object \(jsonObject) with `additionalProperties` is not supported.")
        }
        var `struct` = try transformJSONToStruct(jsonObject)
        `struct` = resolveTransitiveMutableProperties(in: `struct`)
        return `struct`
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
        default:
            throw Exception.unimplemented("Transforming \(json) into `SwiftType` is not supported.")
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
                    return SwiftEnum.Case(label: value, rawValue: .string(value: value))
                case .integer(let value):
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
                var `struct` = try transformJSONToStruct(jsonObject)
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
            return try transformJSONToStruct(jsonObject)
        }
    }

    private func transformJSONToStruct(_ jsonObject: JSONObject) throws -> SwiftStruct {
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
