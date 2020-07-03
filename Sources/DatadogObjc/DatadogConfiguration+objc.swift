/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import class Datadog.Datadog

@objcMembers
public class DDLogsEndpoint: NSObject {
    internal let sdkEndpoint: Datadog.Configuration.LogsEndpoint

    internal init(sdkEndpoint: Datadog.Configuration.LogsEndpoint) {
        self.sdkEndpoint = sdkEndpoint
    }

    // MARK: - Public

    public static func eu() -> DDLogsEndpoint { .init(sdkEndpoint: .eu) }
    public static func us() -> DDLogsEndpoint { .init(sdkEndpoint: .us) }
    public static func custom(url: String) -> DDLogsEndpoint { .init(sdkEndpoint: .custom(url: url)) }
}

@objcMembers
public class DDTracesEndpoint: NSObject {
    internal let sdkEndpoint: Datadog.Configuration.TracesEndpoint

    internal init(sdkEndpoint: Datadog.Configuration.TracesEndpoint) {
        self.sdkEndpoint = sdkEndpoint
    }

    // MARK: - Public

    public static func eu() -> DDTracesEndpoint { .init(sdkEndpoint: .eu) }
    public static func us() -> DDTracesEndpoint { .init(sdkEndpoint: .us) }
    public static func custom(url: String) -> DDTracesEndpoint { .init(sdkEndpoint: .custom(url: url)) }
}

@objcMembers
public class DDConfiguration: NSObject {
    internal let sdkConfiguration: Datadog.Configuration

    internal init(sdkConfiguration: Datadog.Configuration) {
        self.sdkConfiguration = sdkConfiguration
    }

    // MARK: - Public

    public static func builder(clientToken: String, environment: String) -> DDConfigurationBuilder {
        return DDConfigurationBuilder(
            sdkBuilder: Datadog.Configuration.builderUsing(clientToken: clientToken, environment: environment)
        )
    }
}

@objcMembers
public class DDConfigurationBuilder: NSObject {
    internal let sdkBuilder: Datadog.Configuration.Builder

    internal init(sdkBuilder: Datadog.Configuration.Builder) {
        self.sdkBuilder = sdkBuilder
    }

    // MARK: - Public

    @available(*, deprecated, renamed: "set(logsEndpoint:)")
    public func set(endpoint: DDLogsEndpoint) {
        set(logsEndpoint: endpoint)
    }

    public func enableLogging(_ enabled: Bool) {
        _ = sdkBuilder.enableLogging(enabled)
    }

    public func enableTracing(_ enabled: Bool) {
        _ = sdkBuilder.enableTracing(enabled)
    }

    public func set(logsEndpoint: DDLogsEndpoint) {
        _ = sdkBuilder.set(logsEndpoint: logsEndpoint.sdkEndpoint)
    }

    public func set(tracesEndpoint: DDTracesEndpoint) {
        _ = sdkBuilder.set(tracesEndpoint: tracesEndpoint.sdkEndpoint)
    }

    public func set(tracedHosts: Set<String>) {
        _ = sdkBuilder.set(tracedHosts: tracedHosts)
    }

    public func set(serviceName: String) {
        _ = sdkBuilder.set(serviceName: serviceName)
    }

    public func build() -> DDConfiguration {
        return DDConfiguration(sdkConfiguration: sdkBuilder.build())
    }
}
