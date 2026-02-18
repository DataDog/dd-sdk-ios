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

/// Internal attributes, passed from cross-platform bridge or internal integrations.
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

    /// A custom unique id that identifies this build of the application, used from symbolication and deobfuscation
    ///  Id does not replace any default native properties and is sent in addition to version and build number
    public static let buildId: String = "_dd.build_id"

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

    /// Custom attribute passed when starting GraphQL RUM resources from a cross platform SDK.
    /// It sets the GraphQL operation name if it was defined by the developer.
    /// Expects `String` value.
    public static let graphqlOperationName = "_dd.graphql.operation_name"

    /// Custom attribute passed when starting GraphQL RUM resources from a cross platform SDK.
    /// It sets the GraphQL operation type.
    /// Expects `String` value of either `query`, `mutation` or `subscription`.
    public static let graphqlOperationType = "_dd.graphql.operation_type"

    /// Custom attribute passed when starting GraphQL RUM resources from a cross platform SDK.
    /// It sets the GraphQL payload as a JSON string when it is specified.
    /// Expects `String` value.
    public static let graphqlPayload = "_dd.graphql.payload"

    /// Custom attribute passed when starting GraphQL RUM resources resources from a cross platform SDK.
    /// It sets the GraphQL variables as a JSON string if they were defined by the developer.
    /// Expects `String` value.
    public static let graphqlVariables = "_dd.graphql.variables"

    /// Custom attribute passed when completing GraphQL RUM resources that contain errors in the response.
    /// It sets the GraphQL errors array as a JSON string.
    /// Expects `String` value containing a JSON array of errors.
    public static let graphqlErrors = "_dd.graphql.errors"

    /// Override the `source_type` of errors reported by the native crash handler. This is used on
    /// platforms that can supply extra steps or information on a native crash (such as Unity's IL2CPP)
    public static let nativeSourceType = "_dd.native_source_type"

    /// Add "binary images" to the reportted error to assist with symbolication. Used by Unity for IL2CPP symbolicaiton
    public static let includeBinaryImages = "_dd.error.include_binary_images"

    /// Custom Flutter vital - First Build Complete. The amount of time between a route change (the start of a view) and when the first
    /// `build` method is complete. In nanoseconds since view start
    public static let flutterFirstBuildComplete: String = "_dd.performance.first_build_complete"

    /// Custom value for Interaction To Next view.
    /// For Flutter this is the amount of time between an action occurring and the First Build Complete occurring on the next view.
    public static let customINVValue: String = "_dd.view.custom_inv_value"

    /// HTTP headers captured from the resource request, serialized as a JSON string.
    /// Used to transport request headers through the RUM command pipeline.
    /// Expects `String` value containing a JSON dictionary of `[String: String]`.
    public static let resourceRequestHeaders = "_dd.resource.request_headers"

    /// HTTP headers captured from the resource response, serialized as a JSON string.
    /// Used to transport response headers through the RUM command pipeline.
    /// Expects `String` value containing a JSON dictionary of `[String: String]`.
    public static let resourceResponseHeaders = "_dd.resource.response_headers"
}

/// HTTP header names used to pass GraphQL metadata from the application to the SDK.
/// These headers are read from intercepted requests and mapped to internal attributes.
public struct GraphQLHeaders {
    /// HTTP header name for GraphQL operation name.
    public static let operationName: String = "_dd-custom-header-graph-ql-operation-name"

    /// HTTP header name for GraphQL operation type.
    public static let operationType: String = "_dd-custom-header-graph-ql-operation-type"

    /// HTTP header name for GraphQL variables.
    public static let variables: String = "_dd-custom-header-graph-ql-variables"

    /// HTTP header name for GraphQL payload.
    public static let payload: String = "_dd-custom-header-graph-ql-payload"
}

extension URLRequest {
    /// Whether this request contains GraphQL headers indicating a GraphQL request.
    public var hasGraphQLHeaders: Bool {
        value(forHTTPHeaderField: GraphQLHeaders.operationName) != nil ||
        value(forHTTPHeaderField: GraphQLHeaders.operationType) != nil ||
        value(forHTTPHeaderField: GraphQLHeaders.variables) != nil ||
        value(forHTTPHeaderField: GraphQLHeaders.payload) != nil
    }
}

public struct LaunchArguments {
    /// Each product should consider this argument to offer simple debugging experience. 
    /// For example, if this flag is present it can use no sampling.
    public static let Debug = "DD_DEBUG"
}

extension DatadogExtension where ExtendedType == [String: Any] {
    public var swiftAttributes: [String: Encodable] {
        type.mapValues { AnyEncodable($0) }
    }
}

extension DatadogExtension where ExtendedType == [String: Encodable] {
    public var objCAttributes: [String: Any] {
        type.compactMapValues { ($0 as? AnyEncodable)?.value }
    }
}

extension AttributeValue {
    /// Instance Datadog extension point.
    ///
    /// `AttributeValue` aka `Encodable` is a protocol and cannot be extended
    /// with conformance to`DatadogExtension`, so we need to define the `dd`
    /// endpoint.
    public var dd: DatadogExtension<AttributeValue> {
        DatadogExtension(self)
    }
}

extension DatadogExtension where ExtendedType == AttributeValue {
    public func decode<T>(_: T.Type = T.self) -> T? {
        switch type {
        case let encodable as _AnyEncodable:
            return encodable.value as? T
        case let val as T:
            return val
        default:
            return nil
        }
    }
}
