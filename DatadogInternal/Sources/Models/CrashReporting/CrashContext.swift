/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes current Datadog SDK context, so the app state information can be attached to
/// the crash report and retrieved back when the application is started again.
///
/// Note: as it gets saved along with the crash report during process interruption, it's good
/// to keep this data well-packed and as small as possible.
public struct CrashContext: Codable, Equatable {
    /// The Application Launch Date
    public var appLaunchDate: Date?

    /// Interval between device and server time.
    ///
    /// The value can change as the device continue to sync with the server.
    public let serverTimeOffset: TimeInterval

    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public let service: String

    /// The name of the environment that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public let env: String

    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public let version: String

    /// The build number of the application that data is generated from.
    public let buildNumber: String

    /// Current device information.
    public let device: DeviceInfo

    /// The version of Datadog iOS SDK.
    public let sdkVersion: String

    /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
    ///  - See: Datadog [Reserved Attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#reserved-attributes).
    public let source: String

    /// The user's consent to data collection
    public let trackingConsent: TrackingConsent

    /// Current user information.
    public let userInfo: UserInfo?

    /// Current account information
    public let accountInfo: AccountInfo?

    /// Network information.
    ///
    /// Represents the current state of the device network connectivity and interface.
    /// The value can be `unknown` if the network interface is not available or if it has not
    /// yet been evaluated.
    public let networkConnectionInfo: NetworkConnectionInfo?

    /// Carrier information.
    ///
    /// Represents the current telephony service info of the device.
    /// This value can be `nil` of no service is currently registered, or if the device does
    /// not support telephony services.
    public let carrierInfo: CarrierInfo?

    /// The current mobile device battery status.
    ///
    /// This value can be `nil` of the current device battery interface is not available.
    public var batteryStatus: BatteryStatus?

    /// The current brightness status.
    public var brightnessLevel: BrightnessLevel?

    /// `true` if the Low Power Mode is enabled.
    public var isLowPowerModeEnabled = false

    /// The last _"Is app in foreground?"_ information from crashed app process.
    public let lastIsAppInForeground: Bool

    /// The last RUM view in crashed app process.
    public var lastRUMViewEvent: RUMViewEvent?

    /// State of the last RUM session in crashed app process.
    public var lastRUMSessionState: RUMSessionState?

    /// Last global log attributes, set with Logs.addAttribute / Logs.removeAttribute
    public var lastLogAttributes: LogEventAttributes?

    /// Last global RUM attributes. It gets updated with adding or removing attributes on `RUMMonitor`.
    public var lastRUMAttributes: RUMEventAttributes?

    // MARK: - Initialization

    public init(
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
        accountInfo: AccountInfo?,
        networkConnectionInfo: NetworkConnectionInfo?,
        carrierInfo: CarrierInfo?,
        batteryStatus: BatteryStatus?,
        brightnessLevel: BrightnessLevel?,
        isLowPowerModeEnabled: Bool,
        lastIsAppInForeground: Bool,
        appLaunchDate: Date?,
        lastRUMViewEvent: RUMViewEvent?,
        lastRUMSessionState: RUMSessionState?,
        lastRUMAttributes: RUMEventAttributes?,
        lastLogAttributes: LogEventAttributes?
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
        self.accountInfo = accountInfo
        self.networkConnectionInfo = networkConnectionInfo
        self.carrierInfo = carrierInfo
        self.batteryStatus = batteryStatus
        self.brightnessLevel = brightnessLevel
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.lastIsAppInForeground = lastIsAppInForeground
        self.appLaunchDate = appLaunchDate
        self.lastRUMViewEvent = lastRUMViewEvent
        self.lastRUMSessionState = lastRUMSessionState
        self.lastRUMAttributes = lastRUMAttributes
        self.lastLogAttributes = lastLogAttributes
    }

    public init(
        _ context: DatadogContext,
        lastRUMViewEvent: RUMViewEvent?,
        lastRUMSessionState: RUMSessionState?,
        lastRUMAttributes: RUMEventAttributes?,
        lastLogAttributes: LogEventAttributes?
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
        self.accountInfo = context.accountInfo
        self.networkConnectionInfo = context.networkConnectionInfo
        self.carrierInfo = context.carrierInfo
        self.lastIsAppInForeground = context.applicationStateHistory.currentSnapshot.state.isRunningInForeground

        self.lastRUMViewEvent = lastRUMViewEvent
        self.lastRUMSessionState = lastRUMSessionState
        self.lastRUMAttributes = lastRUMAttributes
        self.lastLogAttributes = lastLogAttributes

        self.appLaunchDate = context.launchTime.launchDate
    }

    public static func == (lhs: CrashContext, rhs: CrashContext) -> Bool {
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
        lhs.accountInfo?.id == rhs.accountInfo?.id &&
        lhs.accountInfo?.name == rhs.accountInfo?.name &&
        lhs.appLaunchDate == rhs.appLaunchDate
    }
}
