/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension Datadog: DatadogInternal {}
extension Datadog.Configuration.Builder: DatadogInternal {}

/// This extension exposes internal methods that are used by other Datadog modules and cross platform
/// frameworks. It is not meant for public use.
///
/// DO NOT USE this extension or its methods if you are not working on the internals of the Datadog SDK
/// or one of the cross platform frameworks.
///
/// Methods, members, and functionality of this class  are subject to change without notice, as they
/// are not considered part of the public interface of the Datadog SDK.
extension DatadogExtension where ExtendedType: Datadog {
    /// Internal telemetry proxy.
    public static var telemetry: _TelemetryProxy { .init() }

    /// Changes the `version` used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public static func set(customVersion: String) {
        guard let core = defaultDatadogCore as? DatadogCore else {
            return
        }

        core.applicationVersionPublisher.version = customVersion
    }
}

public struct _TelemetryProxy {
    public func setConfigurationMapper(mapper: @escaping (TelemetryConfigurationEvent) -> TelemetryConfigurationEvent) {
        if let rumTelemetry = DD.telemetry as? RUMTelemetry {
            rumTelemetry.configurationEventMapper = mapper
        }
    }
    /// See Telementry.debug
    public func debug(id: String, message: String) {
        DD.telemetry.debug(id: id, message: message)
    }

    /// See Telementry.error
    public func error(id: String, message: String, kind: String?, stack: String?) {
        DD.telemetry.error(id: id, message: message, kind: kind, stack: stack)
    }
}

extension DatadogExtension where ExtendedType: Datadog.Configuration.Builder {
    /// Sets the custom mapper for `LogEvent`. This can be used to modify logs before they are sent to Datadog.
    ///
    /// - Parameter mapper: the mapper taking `LogEvent` as input and invoke callback closure with modifier `LogEvent`.
    public func setLogEventMapper(_ mapper: LogEventMapper) -> ExtendedType {
        type.configuration.logEventMapper = mapper
        return type
    }
}
