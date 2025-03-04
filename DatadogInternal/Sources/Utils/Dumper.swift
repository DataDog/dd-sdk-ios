/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Protocol for dumping objects to a text stream.
///
/// The `Dumper` protocol provides a standard interface for converting objects to string
/// representations and writing them to a text output stream.
public protocol Dumper {
    func dump<T, TargetStream>(_ value: T, to target: inout TargetStream) where TargetStream: TextOutputStream
}

/// Default implementation of the `Dumper` protocol that uses `customDump` to generate string representations.
///
/// This implementation provides structured output for complex Swift objects by leveraging
/// the `customDump` functionality, which creates more readable output than the standard
/// `print` or `description` approaches.
public class DefaultDumper: Dumper {
    public init() {}

    /// Dumps the value to the target stream using `customDump`.
    ///
    /// - Parameters:
    ///   - value: The value to dump.
    ///   - target: The stream to write the dump to.
    public func dump<T, TargetStream>(_ value: T, to target: inout TargetStream) where TargetStream: TextOutputStream {
        customDump(value, to: &target)
    }
}
