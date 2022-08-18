/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// This class exposes internal methods that are used by other Datadog modules and cross platform
/// frameworks. It is not meant for public use.
///
/// DO NOT USE this class or its methods if you are not working on the internals of the Datadog SDK
/// or one of the cross platform frameworks.
///
/// Methods, members, and functionality of this class  are subject to change without notice, as they
/// are not considered part of the public interface of the Datadog SDK.
public class _InternalProxy {
    public let _configuration = _ConfigurationProxy()
    public let _telemtry = _TelemetryProxy()
}

public class _TelemetryProxy {
    /// See Telementry.debug
    public func debug(id: String, message: String) {
        DD.telemetry.debug(id: id, message: message)
    }

    /// See Telementry.error
    public func error(id: String, message: String, kind: String?, stack: String?) {
        DD.telemetry.error(id: id, message: message, kind: kind, stack: stack)
    }
}

public class _ConfigurationProxy {
    /// Changes the `version` used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    public func set(customVersion: String) {
        guard let core = defaultDatadogCore as? DatadogCore else {
            return
        }

        core.appVersionProvider.value = customVersion
    }
}
