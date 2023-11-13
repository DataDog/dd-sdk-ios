/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// W3C trace context headers as explained in
/// https://www.w3.org/TR/trace-context/#traceparent-header
public enum W3CHTTPHeaders {
    /// The traceparent header represents the incoming request in a tracing system in a common format, understood by all vendors.
    /// It's following a convention of `{version-format}-{trace-id}-{parent-id}-{trace-flags}`.
    ///
    /// Here’s an example of a traceparent header.
    /// `traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01`
    ///
    /// **version-format**
    ///
    /// The following version-format definition is used for version 00.
    ///
    /// **trace-id**
    ///
    /// This is the ID of the whole trace forest and is used to uniquely identify a distributed trace through a system.
    /// It is represented as a 16-byte array, for example, `4bf92f3577b34da6a3ce929d0e0e4736`.
    /// All bytes as zero (`00000000000000000000000000000000`) is considered an invalid value.
    ///
    /// **parent-id**
    ///
    /// This is the ID of this request as known by the caller
    /// (in some tracing systems, this is known as the span-id, where a span is the execution of a client request).
    /// It is represented as an 8-byte array, for example, `00f067aa0ba902b7`.
    /// All bytes as zero (`0000000000000000`) is considered an invalid value.
    ///
    /// **trace-flags**
    ///
    /// The current version of this specification only supports a single flag called sampled.
    /// The sampled flag can be used to ensure that information about requests that were marked
    /// for recording by the caller will also be recorded by SaaS service downstream so that the caller
    /// can troubleshoot the behavior of every recorded request.
    public static let traceparent = "traceparent"

    /// The main purpose of the tracestate HTTP header is to provide additional vendor-specific trace identification
    /// information across different distributed tracing systems and is a companion header for the traceparent field. It
    /// also conveys information about the request’s position in multiple distributed tracing graphs.
    public static let tracestate = "tracestate"

    public enum Constants {
        public static let version = "00"
        public static let sampledValue = "01"
        public static let unsampledValue = "00"
        public static let separator = "-"

        // MARK: - Datadog specific tracestate keys
        public static let dd = "dd"
        public static let sampling = "s"
        public static let origin = "o"
        public static let originRUM = "rum"
        public static let parentId = "p"
        public static let tracestateKeyValueSeparator = ":"
        public static let tracestatePairSeparator = ";"
    }
}
