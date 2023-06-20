/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

/// Any `Encodable` value of the attribute (`String`, `Int`, `Bool`, `Date` etc.).
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

// MARK: - Internal attributes

/// Internal attributes, passed from cross-platform bridge.
/// Used to configure or override SDK internal features and attributes for the need of cross-platform SDKs (e.g. React Native SDK).
public struct CrossPlatformAttributes {
    /// Custom app version passed from CP SDK. Used for all events issued by the SDK (both coming from cross-platform SDK and produced internally, like RUM long tasks).
    /// It should replace the default native `version` read from `Info.plist`.
    /// Expects `String` value (semantic version).
    public static let version: String = "_dd.version"

    /// Custom SDK version passed from CP SDK. Used for all events issued by the SDK (both coming from cross-platform SDK and produced internally, like RUM long tasks).
    /// It should replace the default native `sdkVersion`.
    /// Expects `String` value (semantic version).
    public static let sdkVersion: String = "_dd.sdk_version"

    /// Custom SDK `source` passed from CP SDK. Used for all events issued by the SDK (both coming from cross-platform SDK and produced internally, like RUM long tasks).
    /// It should replace the default native `ddsource` value (`"ios"`).
    /// Expects `String` value.
    public static let ddsource: String = "_dd.source"

    /// Custom Variant passed from a CP SDK. This is the 'flavor' parameter used in Android and Flutter, Used for all events issued by the SDK (both coming from cross-platform
    /// SDK and produced internally, like RUM long tasks).
    /// It does not replace any default native properties as iOS does not have the concept of 'flavors' or variants.
    public static let variant: String = "_dd.variant"

    /// Event timestamp passed from CP SDK. Used for all RUM events issued by cross platform SDK.
    /// It should replace event time obtained from `DateProvider` to ensure that events are not skewed due to time difference in native and cross-platform SDKs.
    /// Expects `Int64` value (milliseconds).
    public static let timestampInMilliseconds = "_dd.timestamp"

    /// Custom "source type" of the error passed from CP SDK. Used in RUM errors reported by cross platform SDK.
    /// It names the language or platform of the RUM error stack trace, so the SCI backend knows how to symbolicate it.
    /// Expects `String` value.
    public static let errorSourceType = "_dd.error.source_type"

    /// Custom attribute of the error passed from CP SDK. Used in RUM errors reported by cross platform SDK.
    /// It flags the error has being fatal for the host application.
    /// Expects `Bool` value.
    public static let errorIsCrash = "_dd.error.is_crash"

    /// Trace ID passed from CP SDK. Used in RUM resources created by cross platform SDK.
    /// When cross-platform SDK injects tracing headers to intercepted resource, we pass tracing information through this attribute
    /// and send it within the RUM resource, so the RUM backend can issue corresponding APM span on behalf of the mobile app.
    /// Expects `String` value.
    public static let traceID = "_dd.trace_id"

    /// Span ID passed from CP SDK. Used in RUM resources created by cross platform SDK.
    /// When cross-platform SDK injects tracing headers to intercepted resource, we pass tracing information through this attribute
    /// and send it within the RUM resource, so the RUM backend can issue corresponding APM span on behalf of the mobile app.
    /// Expects `String` value.
    public static let spanID = "_dd.span_id"

    /// Trace sample rate applied to RUM resources created by cross platform SDK.
    /// We send cross-platform SDK's sample rate within RUM resource in order to provide accurate visibility into what settings are
    /// configured at the SDK level. This gets displayed on APM's traffic ingestion control page.
    /// Expects `Double` value between `0.0` and `1.0`.
    public static let rulePSR = "_dd.rule_psr"

    /// Custom attribute of the log passed from CP SDK. Used in error logs reported by cross platform SDK.
    /// It flags the error has being fatal for the host application, so we can prevent creating a duplicate RUM error.
    /// The goal of RUMM-3289 is to create an RFC to get rid of this mechanism.
    /// Expects `Bool` value.
    public static let errorLogIsCrash = "_dd.error_log.is_crash"
}
