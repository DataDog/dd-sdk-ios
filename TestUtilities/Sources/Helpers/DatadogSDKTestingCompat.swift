/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(DatadogSDKTesting)
@_exported import DatadogSDKTesting
#else
import Testing

/// No-op stand-in for `DatadogSDKTesting`'s `.datadogTesting` trait.
///
/// `DatadogSDKTesting` (https://github.com/DataDog/dd-sdk-swift-testing) requires iOS 15+,
/// while this package's platform floor is iOS 12 — SwiftPM has no per-target deployment
/// override, so it can't be declared as a `Package.swift` dependency. It is only ever
/// resolved when building through `Datadog.xcworkspace`, which links it directly. When
/// building via `Package.swift` (`swift build`/`swift test`), this stub is used instead so
/// `@Suite(.datadogTesting)` still compiles, without observing anything.
public struct DatadogSDKTestingStubTrait: TestTrait, SuiteTrait {
    public let isRecursive = true
}

extension Trait where Self == DatadogSDKTestingStubTrait {
    public static var datadogTesting: Self { Self() }
}

/// Stand-in for `DatadogSDKTesting`'s `Tag.dd.retriable`/`.nonretriable` and
/// `Tag.dd.tia.skippable`/`.unskippable` tags. Applying any of these tags under the
/// stub is a no-op.
extension Tag {
    public enum dd {
        @Tag public static var retriable: Tag
        @Tag public static var nonretriable: Tag

        public enum tia {
            @Tag public static var skippable: Tag
            @Tag public static var unskippable: Tag
        }
    }
}
#endif
