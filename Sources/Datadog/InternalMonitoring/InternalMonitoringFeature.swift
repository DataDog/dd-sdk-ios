/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains subdirectories in `/Library/Caches` where internal monitoring data is stored.
internal func obtainInternalMonitoringFeatureLogDirectories() throws -> FeatureDirectories {
    let version = "v1"
    return FeatureDirectories(
        unauthorized: try Directory(withSubdirectoryPath: "com.datadoghq.im-logs/intermediate-\(version)"),
        authorized: try Directory(withSubdirectoryPath: "com.datadoghq.im-logs/\(version)")
    )
}

/// This feature provides observability for internal events happening in the SDK. All data collected by this feature
/// is sent to Datadog org, not to the customer's org. This feature is opt-in and requires specific configuration to be enabled.
/// It is never enabled by default. We do not collect any internal monitoring data for those who didn't explicitly opt-in for that by contacting Datadog.
///
/// This feature uses Datadog logs for sending observability data.
///
/// The `InternalMonitoringFeature` facade creates and owns components enabling the feature.
/// Bundles dependencies for monitoring-related components created later at runtime  (i.e. internal `Logger`).
internal final class InternalMonitoringFeature {
    /// Single, shared instance of `InternalMonitoringFeature`.
    internal static var instance: InternalMonitoringFeature?

    /// Tells if the feature was enabled by the user in the SDK configuration.
    static var isEnabled: Bool { instance != nil }

    // MARK: - Components

    static let featureName = "internal-monitoring"
    /// NOTE: any change to data format requires updating the directory url to be unique
    static let logsDataFormat = DataFormat(prefix: "[", suffix: "]", separator: ",")

    /// Log files storage.
    let logsStorage: FeatureStorage
    /// Logs upload worker.
    let logsUpload: FeatureUpload

    /// Monitor bundling internal monitoring tools for `dd-sdk-ios` observability in Datadog org.
    let monitor: InternalMonitor

    // MARK: - Initialization

    static func createLogsStorage(directories: FeatureDirectories, commonDependencies: FeaturesCommonDependencies) -> FeatureStorage {
        return FeatureStorage(
            featureName: InternalMonitoringFeature.featureName,
            dataFormat: InternalMonitoringFeature.logsDataFormat,
            directories: directories,
            commonDependencies: commonDependencies,
            // (!) Do not inject monitoring bundle, otherwise the feature will be monitoring itself
            // leading to infinite processing loops.
            internalMonitor: nil
        )
    }

    static func createLogsUpload(
        storage: FeatureStorage,
        configuration: FeaturesConfiguration.InternalMonitoring,
        commonDependencies: FeaturesCommonDependencies
    ) -> FeatureUpload {
        return FeatureUpload(
            featureName: InternalMonitoringFeature.featureName,
            storage: storage,
            requestBuilder: RequestBuilder(
                url: configuration.logsUploadURL,
                queryItems: [
                    .ddsource(source: configuration.common.source)
                ],
                headers: [
                    .contentTypeHeader(contentType: .applicationJSON),
                    .userAgentHeader(
                        appName: configuration.common.applicationName,
                        appVersion: configuration.common.applicationVersion,
                        device: commonDependencies.mobileDevice
                    ),
                    .ddAPIKeyHeader(clientToken: configuration.clientToken),
                    .ddEVPOriginHeader(source: configuration.common.source),
                    .ddEVPOriginVersionHeader(),
                    .ddRequestIDHeader(),
                ],
                // (!) Do not inject monitoring bundle, otherwise the feature will be monitoring itself
                // leading to infinite processing loops.
                internalMonitor: nil
            ),
            commonDependencies: commonDependencies,
            // (!) Do not inject monitoring bundle, otherwise the feature will be monitoring itself
            // leading to infinite processing loops.
            internalMonitor: nil
        )
    }

    convenience init(
        logDirectories: FeatureDirectories,
        configuration: FeaturesConfiguration.InternalMonitoring,
        commonDependencies: FeaturesCommonDependencies
    ) {
        let storage = InternalMonitoringFeature.createLogsStorage(directories: logDirectories, commonDependencies: commonDependencies)
        let upload = InternalMonitoringFeature.createLogsUpload(storage: storage, configuration: configuration, commonDependencies: commonDependencies)
        self.init(
            storage: storage,
            upload: upload,
            configuration: configuration,
            commonDependencies: commonDependencies
        )
    }

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: FeaturesConfiguration.InternalMonitoring,
        commonDependencies: FeaturesCommonDependencies
    ) {
        // Initialize stacks
        self.logsStorage = storage
        self.logsUpload = upload

        // Initialize internal monitor
        let internalLogger = Logger(
            logBuilder: LogEventBuilder(
                applicationVersion: configuration.common.applicationVersion,
                environment: configuration.sdkEnvironment,
                serviceName: configuration.sdkServiceName,
                loggerName: configuration.loggerName,
                userInfoProvider: UserInfoProvider(), // no-op to not associate user info with internal logs
                networkConnectionInfoProvider: commonDependencies.networkConnectionInfoProvider,
                carrierInfoProvider: commonDependencies.carrierInfoProvider,
                dateCorrector: commonDependencies.dateCorrector,
                logEventMapper: nil
            ),
            logOutput: LogFileOutput(
                fileWriter: storage.writer,
                rumErrorsIntegration: nil
            ),
            dateProvider: commonDependencies.dateProvider,
            identifier: configuration.loggerName,
            rumContextIntegration: nil,
            activeSpanIntegration: nil
        )

        internalLogger.addAttribute(forKey: "application.name", value: configuration.common.applicationName)
        internalLogger.addAttribute(forKey: "application.bundle-id", value: configuration.common.applicationBundleIdentifier)

        self.monitor = InternalMonitor(sdkLogger: internalLogger)
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func deinitialize() {
        logsStorage.flushAndTearDown()
        logsUpload.flushAndTearDown()
        InternalMonitoringFeature.instance = nil
    }
#endif
}
