/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct DatadogContext {
    // MARK: - Datadog Specific

    /// [Datadog Site](https://docs.datadoghq.com/getting_started/site/) for data uploads. It can be `nil` in V1
    /// if the SDK is configured using deprecated APIs:
    /// `set(logsEndpoint:)`, `set(tracesEndpoint:)` and `set(rumEndpoint:)`.
    public let site: DatadogSite

    /// The client token allowing for data uploads to [Datadog Site](https://docs.datadoghq.com/getting_started/site/).
    public let clientToken: String

    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public let service: String

    /// The name of the environment that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public let env: String

    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public var version: String

    /// The build number of the application that data is generated from.
    public let buildNumber: String

    /// The id of the build, specifically for cross platform frameworks
    public let buildId: String?

    /// The variant of the build, equivelent to Android's "Flavor".  Only used by cross platform SDKs
    public let variant: String?

    /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
    ///  - See: Datadog [Reserved Attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#reserved-attributes).
    public let source: String

    /// Denotes the source type for  crashes. This is used for platforms that provide additional symbolication steps for native crashes.
    public let nativeSourceOverride: String?

    /// The version of Datadog iOS SDK.
    public let sdkVersion: String

    /// The name of [CI Visibility](https://docs.datadoghq.com/continuous_integration/) origin.
    /// It is only set if the SDK is running with a context passed from [Swift Tests](https://docs.datadoghq.com/continuous_integration/setup_tests/swift/?tab=swiftpackagemanager) library.
    public let ciAppOrigin: String?

    /// Interval between device and server time.
    ///
    /// The value can change as the device continue to sync with the server.
    public var serverTimeOffset: TimeInterval = .zero

    // MARK: - Application Specific

    /// The name of the application, read from `Info.plist` (`CFBundleExecutable`).
    public let applicationName: String

    /// The bundle identifier, read from `Info.plist` (`CFBundleIdentifier`).
    public let applicationBundleIdentifier: String

    /// The type of the bundle running the SDK.
    public let applicationBundleType: BundleType

    /// Date of SDK initialization measured in device time (without NTP correction).
    public let sdkInitDate: Date

    /// Current device information.
    public let device: DeviceInfo

    /// Current user information.
    public var userInfo: UserInfo?

    /// The user's consent to data collection
    public var trackingConsent: TrackingConsent = .pending

    /// Application launch time.
    ///
    /// Can be `nil` if the launch could not yet been evaluated.
    public var launchTime: LaunchTime?

    /// Provides the history of app foreground / background states.
    public var applicationStateHistory: AppStateHistory

    // MARK: - Device Specific

    /// Network information.
    ///
    /// Represents the current state of the device network connectivity and interface.
    /// The value can be `unknown` if the network interface is not available or if it has not
    /// yet been evaluated.
    public var networkConnectionInfo: NetworkConnectionInfo?

    /// Carrier information.
    ///
    /// Represents the current telephony service info of the device.
    /// This value can be `nil` of no service is currently registered, or if the device does
    /// not support telephony services.
    public var carrierInfo: CarrierInfo?

    /// The current mobile device battery status.
    ///
    /// This value can be `nil` of the current device battery interface is not available.
    public var batteryStatus: BatteryStatus?

    /// `true` if the Low Power Mode is enabled.
    public var isLowPowerModeEnabled = false

    /// Type-less context baggages.
    public var baggages: [String: FeatureBaggage] = [:]

    // swiftlint:disable function_default_parameter_at_end
    public init(
        site: DatadogSite,
        clientToken: String,
        service: String,
        env: String,
        version: String,
        buildNumber: String,
        buildId: String?,
        variant: String?,
        source: String,
        sdkVersion: String,
        ciAppOrigin: String?,
        serverTimeOffset: TimeInterval = .zero,
        applicationName: String,
        applicationBundleIdentifier: String,
        applicationBundleType: BundleType,
        sdkInitDate: Date,
        device: DeviceInfo,
        nativeSourceOverride: String? = nil,
        userInfo: UserInfo? = nil,
        trackingConsent: TrackingConsent = .pending,
        launchTime: LaunchTime? = nil,
        applicationStateHistory: AppStateHistory,
        networkConnectionInfo: NetworkConnectionInfo? = nil,
        carrierInfo: CarrierInfo? = nil,
        batteryStatus: BatteryStatus? = nil,
        isLowPowerModeEnabled: Bool = false,
        baggages: [String: FeatureBaggage] = [:]
    ) {
        self.site = site
        self.clientToken = clientToken
        self.service = service
        self.env = env
        self.version = version
        self.buildNumber = buildNumber
        self.buildId = buildId
        self.variant = variant
        self.source = source
        self.sdkVersion = sdkVersion
        self.ciAppOrigin = ciAppOrigin
        self.serverTimeOffset = serverTimeOffset
        self.applicationName = applicationName
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationBundleType = applicationBundleType
        self.sdkInitDate = sdkInitDate
        self.device = device
        self.nativeSourceOverride = nativeSourceOverride
        self.userInfo = userInfo
        self.trackingConsent = trackingConsent
        self.launchTime = launchTime
        self.applicationStateHistory = applicationStateHistory
        self.networkConnectionInfo = networkConnectionInfo
        self.carrierInfo = carrierInfo
        self.batteryStatus = batteryStatus
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.baggages = baggages
    }
    // swiftlint:enable function_default_parameter_at_end
}
