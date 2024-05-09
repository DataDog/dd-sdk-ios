/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Describes current Datadog SDK context, so the app state information can be attached to
/// the crash report and retrieved back when the application is started again.
///
/// Note: as it gets saved along with the crash report during process interruption, it's good
/// to keep this data well-packed and as small as possible.
internal struct CrashContext: Codable, Equatable {
    /// The Application Launch Date
    var appLaunchDate: Date?

    /// Interval between device and server time.
    ///
    /// The value can change as the device continue to sync with the server.
    let serverTimeOffset: TimeInterval

    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let service: String

    /// The name of the environment that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let env: String

    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let version: String

    /// The build number of the application that data is generated from.
    let buildNumber: String

    /// Current device information.
    let device: DeviceInfo

    /// The version of Datadog iOS SDK.
    let sdkVersion: String

    /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
    ///  - See: Datadog [Reserved Attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#reserved-attributes).
    let source: String

    /// The user's consent to data collection
    let trackingConsent: TrackingConsent

    /// Current user information.
    let userInfo: UserInfo?

    /// Network information.
    ///
    /// Represents the current state of the device network connectivity and interface.
    /// The value can be `unknown` if the network interface is not available or if it has not
    /// yet been evaluated.
    let networkConnectionInfo: NetworkConnectionInfo?

    /// Carrier information.
    ///
    /// Represents the current telephony service info of the device.
    /// This value can be `nil` of no service is currently registered, or if the device does
    /// not support telephony services.
    let carrierInfo: CarrierInfo?

    /// The last RUM view in crashed app process.
    var lastRUMViewEvent: AnyCodable?

    /// State of the last RUM session in crashed app process.
    var lastRUMSessionState: AnyCodable?

    /// The last _"Is app in foreground?"_ information from crashed app process.
    let lastIsAppInForeground: Bool

    /// Last global log attributes, set with Logs.addAttribute / Logs.removeAttribute
    var lastLogAttributes: AnyCodable?

    // MARK: - Initialization

    init(
        serverTimeOffset: TimeInterval,
        service: String,
        env: String,
        version: String,
        buildNumber: String,
        device: DeviceInfo,
        sdkVersion: String,
        source: String,
        trackingConsent: TrackingConsent,
        userInfo: UserInfo?,
        networkConnectionInfo: NetworkConnectionInfo?,
        carrierInfo: CarrierInfo?,
        lastRUMViewEvent: AnyCodable?,
        lastRUMSessionState: AnyCodable?,
        lastIsAppInForeground: Bool,
        lastLogAttributes: AnyCodable?,
        appLaunchDate: Date?
    ) {
        self.serverTimeOffset = serverTimeOffset
        self.service = service
        self.env = env
        self.version = version
        self.buildNumber = buildNumber
        self.device = device
        self.sdkVersion = service
        self.source = source
        self.trackingConsent = trackingConsent
        self.userInfo = userInfo
        self.networkConnectionInfo = networkConnectionInfo
        self.carrierInfo = carrierInfo
        self.lastRUMViewEvent = lastRUMViewEvent
        self.lastRUMSessionState = lastRUMSessionState
        self.lastIsAppInForeground = lastIsAppInForeground
        self.lastLogAttributes = lastLogAttributes
        self.appLaunchDate = appLaunchDate
    }

    init(
        _ context: DatadogContext,
        lastRUMViewEvent: AnyCodable?,
        lastRUMSessionState: AnyCodable?,
        lastLogAttributes: AnyCodable?
    ) {
        self.serverTimeOffset = context.serverTimeOffset
        self.service = context.service
        self.env = context.env
        self.version = context.version
        self.buildNumber = context.buildNumber
        self.device = context.device
        self.sdkVersion = context.sdkVersion
        self.source = context.source
        self.trackingConsent = context.trackingConsent
        self.userInfo = context.userInfo
        self.networkConnectionInfo = context.networkConnectionInfo
        self.carrierInfo = context.carrierInfo
        self.lastIsAppInForeground = context.applicationStateHistory.currentSnapshot.state.isRunningInForeground

        self.lastRUMViewEvent = lastRUMViewEvent
        self.lastRUMSessionState = lastRUMSessionState
        self.lastLogAttributes = lastLogAttributes

        self.appLaunchDate = context.launchTime?.launchDate
    }

    static func == (lhs: CrashContext, rhs: CrashContext) -> Bool {
        lhs.serverTimeOffset == rhs.serverTimeOffset &&
            lhs.service == rhs.service &&
            lhs.env == rhs.env &&
            lhs.version == rhs.version &&
            lhs.buildNumber == rhs.buildNumber &&
            lhs.source == rhs.source &&
            lhs.trackingConsent == rhs.trackingConsent &&
            lhs.networkConnectionInfo == rhs.networkConnectionInfo &&
            lhs.carrierInfo == rhs.carrierInfo &&
            lhs.lastIsAppInForeground == rhs.lastIsAppInForeground &&
            lhs.userInfo?.id == rhs.userInfo?.id &&
            lhs.userInfo?.name == rhs.userInfo?.name &&
            lhs.userInfo?.email == rhs.userInfo?.email &&
            lhs.appLaunchDate == rhs.appLaunchDate
    }
}
