/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A `String` value naming the attribute.
///
/// Dot syntax can be used to nest objects:
///
///     logger.addAttribute(forKey: "person.name", value: "Adam")
///     logger.addAttribute(forKey: "person.age", value: 32)
///
///     // When seen in Datadog console:
///     {
///         person: {
///             name: "Adam"
///             age: 32
///         }
///     }
///
/// - Important
/// Values can be nested up to 8 levels deep. Keys using more than 8 levels will be sanitized by the SDK.
///
public typealias AttributeKey = String

/// Any `Ecodable` value of the attribute (`String`, `Int`, `Bool`, `Date` etc.).
///
/// Custom `Encodable` types are supported as well with nested encoding containers:
///
///     struct Person: Codable {
///         let name: String
///         let age: Int
///         let address: Address
///     }
///
///     struct Address: Codable {
///         let city: String
///         let street: String
///     }
///
///     let address = Address(city: "Paris", street: "Champs Elysees")
///     let person = Person(name: "Adam", age: 32, address: address)
///
///     // When seen in Datadog console:
///     {
///         person: {
///             name: "Adam"
///             age: 32
///             address: {
///                 city: "Paris",
///                 street: "Champs Elysees"
///             }
///         }
///     }
///
/// - Important
/// Attributes in Datadog console can be nested up to 10 levels deep. If number of nested attribute levels
/// defined as sum of key levels and value levels exceeds 10, the data may not be delivered.
///
public typealias AttributeValue = Encodable
