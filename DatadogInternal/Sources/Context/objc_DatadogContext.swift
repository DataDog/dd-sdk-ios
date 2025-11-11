/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Objective-C compatible representation of `DatadogContext`.
///
/// This class exposes a subset of `DatadogContext` properties that can be represented in Objective-C.
/// For accessing complex Swift-only types (like `DeviceInfo`, `OperatingSystem`, etc.), use the
/// Swift API directly via the `swiftContext` property on `objc_DatadogContextSubscriber`.
@objc(DDDatadogContext)
@objcMembers
@_spi(objc)
public final class objc_DatadogContext: NSObject {
    // MARK: - Datadog Specific

    /// The Datadog site URL string for data uploads.
    public let siteURL: String

    /// The client token allowing for data uploads to Datadog Site.
    public let clientToken: String

    /// The name of the service that data is generated from.
    public let service: String

    /// The name of the environment that data is generated from.
    public let env: String

    /// The version of the application that data is generated from.
    public let version: String

    /// The build number of the application that data is generated from.
    public let buildNumber: String

    /// The id of the build, specifically for cross platform frameworks.
    public let buildId: String?

    /// The variant of the build, equivalent to Android's "Flavor". Only used by cross platform SDKs.
    public let variant: String?

    /// Denotes the mobile application's platform, such as "ios" or "flutter" that data is generated from.
    public let source: String

    /// Denotes the source type for crashes. This is used for platforms that provide additional symbolication steps for native crashes.
    public let nativeSourceOverride: String?

    /// The version of Datadog iOS SDK.
    public let sdkVersion: String

    /// The name of CI Visibility origin.
    public let ciAppOrigin: String?

    /// Interval between device and server time.
    public let serverTimeOffset: TimeInterval

    // MARK: - Application Specific

    /// The name of the application, read from Info.plist (CFBundleExecutable).
    public let applicationName: String

    /// The bundle identifier, read from Info.plist (CFBundleIdentifier).
    public let applicationBundleIdentifier: String

    /// Date of SDK initialization measured in device time (without NTP correction).
    public let sdkInitDate: Date

    /// `true` if the Low Power Mode is enabled.
    public let isLowPowerModeEnabled: Bool

    /// The underlying Swift `DatadogContext`.
    ///
    /// Use this property to access the full Swift context with all complex types.
    public let swiftContext: DatadogContext

    /// Creates a new instance from a Swift `DatadogContext`.
    ///
    /// - Parameter context: The Swift `DatadogContext` to convert.
    public init(swiftContext context: DatadogContext) {
        self.siteURL = context.site.endpoint.absoluteString
        self.clientToken = context.clientToken
        self.service = context.service
        self.env = context.env
        self.version = context.version
        self.buildNumber = context.buildNumber
        self.buildId = context.buildId
        self.variant = context.variant
        self.source = context.source
        self.nativeSourceOverride = context.nativeSourceOverride
        self.sdkVersion = context.sdkVersion
        self.ciAppOrigin = context.ciAppOrigin
        self.serverTimeOffset = context.serverTimeOffset
        self.applicationName = context.applicationName
        self.applicationBundleIdentifier = context.applicationBundleIdentifier
        self.sdkInitDate = context.sdkInitDate
        self.isLowPowerModeEnabled = context.isLowPowerModeEnabled
        self.swiftContext = context
        super.init()
    }
}
