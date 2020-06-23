/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// A collection of standard `Span` tag keys defined by Open Tracing.
/// Use them as the `key` in `span.setTag(key:value:)`. Use the expected type for the `value`.
///
/// See more: [Span tags table](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#span-tags-table)
///
public struct OTTags {
    /// Expected value: `String`.
    public static let component = "component"

    /// Expected value: `String`
    public static let dbInstance = "db.instance"

    /// Expected value: `String`
    public static let dbStatement = "db.statement"

    /// Expected value: `String`
    public static let dbType = "db.type"

    /// Expected value: `String`
    public static let dbUser = "db.user"

    /// Expected value: `Bool`
    public static let error = "error"

    /// Expected value: `String`
    public static let httpMethod = "http.method"

    /// Expected value: `Int`
    public static let httpStatusCode = "http.status_code"

    /// Expected value: `String`
    public static let httpUrl = "http.url"

    /// Expected value: `String`
    public static let messageBusDestination = "message_bus.destination"

    /// Expected value: `String`
    public static let peerAddress = "peer.address"

    /// Expected value: `String`
    public static let peerHostname = "peer.hostname"

    /// Expected value: `String`
    public static let peerIPv4 = "peer.ipv4"

    /// Expected value: `String`
    public static let peerIPv6 = "peer.ipv6"

    /// Expected value: `Int`
    public static let peerPort = "peer.port"

    /// Expected value: `String`
    public static let peerService = "peer.service"

    /// Expected value: `Int`
    public static let samplingPriority = "sampling.priority"

    /// Expected value: `String`
    public static let spanKind = "span.kind"
}

/// A collection of standard `Span` log fields defined by Open Tracing.
/// Use them as the `key` for `fields` dictionary in `span.log(fields:)`. Use the expected type for the value.
///
/// See more: [Log fields table](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#log-fields-table)
///
public struct OTLogFields {
    /// Expected value: `String`
    public static let errorKind = "error.kind"

    /// Expected value: `String`
    public static let event = "event"

    /// Expected value: `String`
    public static let message = "message"

    /// Expected value: `String`
    public static let stack = "stack"
}
