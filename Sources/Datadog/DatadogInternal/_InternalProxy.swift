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
    let _telemtry = _TelemetryProxy()
}

public class _TelemetryProxy {
    /// See Telementry.debug
    func debug(id: String, message: String) {
        DD.telemetry.debug(id: id, message: message)
    }

    /// See Telementry.error
    func error(id: String, message: String, kind: String?, stack: String?) {
        DD.telemetry.error(id: id, message: message, kind: kind, stack: stack)
    }
}
