/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objc
public class DDEndpoint: NSObject {
    internal let sdkEndpoint: Datadog.Configuration.DatadogEndpoint

    internal init(sdkEndpoint: Datadog.Configuration.DatadogEndpoint) {
        self.sdkEndpoint = sdkEndpoint
    }

    // MARK: - Public

    @objc
    public static func eu() -> DDEndpoint { .init(sdkEndpoint: .eu) }

    @objc
    public static func us() -> DDEndpoint { .init(sdkEndpoint: .us) }

    @objc
    public static func gov() -> DDEndpoint { .init(sdkEndpoint: .gov) }
}

@objc
public class DDLogsEndpoint: NSObject {
    internal let sdkEndpoint: Datadog.Configuration.LogsEndpoint

    internal init(sdkEndpoint: Datadog.Configuration.LogsEndpoint) {
        self.sdkEndpoint = sdkEndpoint
    }

    // MARK: - Public

    @objc
    public static func eu() -> DDLogsEndpoint { .init(sdkEndpoint: .eu) }

    @objc
    public static func us() -> DDLogsEndpoint { .init(sdkEndpoint: .us) }

    @objc
    public static func gov() -> DDLogsEndpoint { .init(sdkEndpoint: .gov) }

    @objc
    public static func custom(url: String) -> DDLogsEndpoint { .init(sdkEndpoint: .custom(url: url)) }
}

@objc
public class DDTracesEndpoint: NSObject {
    internal let sdkEndpoint: Datadog.Configuration.TracesEndpoint

    internal init(sdkEndpoint: Datadog.Configuration.TracesEndpoint) {
        self.sdkEndpoint = sdkEndpoint
    }

    // MARK: - Public

    @objc
    public static func eu() -> DDTracesEndpoint { .init(sdkEndpoint: .eu) }

    @objc
    public static func us() -> DDTracesEndpoint { .init(sdkEndpoint: .us) }

    @objc
    public static func gov() -> DDTracesEndpoint { .init(sdkEndpoint: .gov) }

    @objc
    public static func custom(url: String) -> DDTracesEndpoint { .init(sdkEndpoint: .custom(url: url)) }
}

@objc
public enum DDBatchSize: Int {
    case small
    case medium
    case large

    internal var swiftType: Datadog.Configuration.BatchSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }
}

@objc
public enum DDUploadFrequency: Int {
    case frequent
    case average
    case rare

    internal var swiftType: Datadog.Configuration.UploadFrequency {
        switch self {
        case .frequent: return .frequent
        case .average: return .average
        case .rare: return .rare
        }
    }
}

@objc
public class DDConfiguration: NSObject {
    internal let sdkConfiguration: Datadog.Configuration

    internal init(sdkConfiguration: Datadog.Configuration) {
        self.sdkConfiguration = sdkConfiguration
    }

    // MARK: - Public

    @objc
    public static func builder(clientToken: String, environment: String) -> DDConfigurationBuilder {
        return DDConfigurationBuilder(
            sdkBuilder: Datadog.Configuration.builderUsing(clientToken: clientToken, environment: environment)
        )
    }

    @objc
    public static func builder(rumApplicationID: String, clientToken: String, environment: String) -> DDConfigurationBuilder {
        return DDConfigurationBuilder(
            sdkBuilder: Datadog.Configuration
                .builderUsing(rumApplicationID: rumApplicationID, clientToken: clientToken, environment: environment)
        )
    }
}

@objc
public class DDConfigurationBuilder: NSObject {
    internal let sdkBuilder: Datadog.Configuration.Builder

    internal init(sdkBuilder: Datadog.Configuration.Builder) {
        self.sdkBuilder = sdkBuilder
    }

    // MARK: - Public

    @objc
    public func enableLogging(_ enabled: Bool) {
        _ = sdkBuilder.enableLogging(enabled)
    }

    @objc
    public func enableTracing(_ enabled: Bool) {
        _ = sdkBuilder.enableTracing(enabled)
    }

    @objc
    public func enableRUM(_ enabled: Bool) {
        _ = sdkBuilder.enableRUM(enabled)
    }

    @objc
    public func set(endpoint: DDEndpoint) {
        _ = sdkBuilder.set(endpoint: endpoint.sdkEndpoint)
    }

    @objc
    public func set(customLogsEndpoint: URL) {
        _ = sdkBuilder.set(customLogsEndpoint: customLogsEndpoint)
    }

    @objc
    public func set(customTracesEndpoint: URL) {
        _ = sdkBuilder.set(customTracesEndpoint: customTracesEndpoint)
    }

    @objc
    public func set(customRUMEndpoint: URL) {
        _ = sdkBuilder.set(customRUMEndpoint: customRUMEndpoint)
    }

    @available(*, deprecated, message: "This option is replaced by `set(endpoint:)`. Refer to the new API comment for details.")
    @objc
    public func set(logsEndpoint: DDLogsEndpoint) {
        _ = sdkBuilder.set(logsEndpoint: logsEndpoint.sdkEndpoint)
    }

    @available(*, deprecated, message: "This option is replaced by `set(endpoint:)`. Refer to the new API comment for details.")
    @objc
    public func set(tracesEndpoint: DDTracesEndpoint) {
        _ = sdkBuilder.set(tracesEndpoint: tracesEndpoint.sdkEndpoint)
    }

    @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
    @objc
    public func set(tracedHosts: Set<String>) {
        track(firstPartyHosts: tracedHosts)
    }

    @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
    @objc
    public func track(firstPartyHosts: Set<String>) {
        trackURLSession(firstPartyHosts: firstPartyHosts)
    }

    @objc
    public func trackURLSession(firstPartyHosts: Set<String>) {
        _ = sdkBuilder.trackURLSession(firstPartyHosts: firstPartyHosts)
    }

    @objc
    public func set(serviceName: String) {
        _ = sdkBuilder.set(serviceName: serviceName)
    }

    @objc
    public func set(rumSessionsSamplingRate: Float) {
        _ = sdkBuilder.set(rumSessionsSamplingRate: rumSessionsSamplingRate)
    }

    @objc
    public func trackUIKitRUMViews() {
        let defaultPredicate = DefaultUIKitRUMViewsPredicate()
        _ = sdkBuilder.trackUIKitRUMViews(using: defaultPredicate)
    }

    @objc
    public func trackUIKitRUMViews(using predicate: DDUIKitRUMViewsPredicate) {
        let predicateBridge = UIKitRUMViewsPredicateBridge(objcPredicate: predicate)
        _ = sdkBuilder.trackUIKitRUMViews(using: predicateBridge)
    }

    @objc
    public func trackUIKitActions() {
        _ = sdkBuilder.trackUIKitActions(true)
    }

    @objc
    public func setRUMViewEventMapper(_ mapper: @escaping (DDRUMViewEvent) -> DDRUMViewEvent?) {
        _ = sdkBuilder.setRUMViewEventMapper { swiftEvent in
            let objcEvent = DDRUMViewEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc
    public func setRUMResourceEventMapper(_ mapper: @escaping (DDRUMResourceEvent) -> DDRUMResourceEvent?) {
        _ = sdkBuilder.setRUMResourceEventMapper { swiftEvent in
            let objcEvent = DDRUMResourceEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc
    public func setRUMActionEventMapper(_ mapper: @escaping (DDRUMActionEvent) -> DDRUMActionEvent?) {
        _ = sdkBuilder.setRUMActionEventMapper { swiftEvent in
            let objcEvent = DDRUMActionEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc
    public func setRUMErrorEventMapper(_ mapper: @escaping (DDRUMErrorEvent) -> DDRUMErrorEvent?) {
        _ = sdkBuilder.setRUMErrorEventMapper { swiftEvent in
            let objcEvent = DDRUMErrorEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc
    public func set(batchSize: DDBatchSize) {
        _ = sdkBuilder.set(batchSize: batchSize.swiftType)
    }

    @objc
    public func set(uploadFrequency: DDUploadFrequency) {
        _ = sdkBuilder.set(uploadFrequency: uploadFrequency.swiftType)
    }

    @objc
    public func set(additionalConfiguration: [String: Any]) {
        _ = sdkBuilder.set(additionalConfiguration: additionalConfiguration)
    }

    @objc
    public func build() -> DDConfiguration {
        return DDConfiguration(sdkConfiguration: sdkBuilder.build())
    }
}
