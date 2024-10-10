/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogCore

@objc
public class DDInternalLogger: NSObject {
    /// Function printing `String` content to console. Intended to be used only by SDK components.
    @objc
    public static func consolePrint(_ message: String, _ level: DDCoreLoggerLevel) {
        let coreLoggerLevel: CoreLoggerLevel = switch level {
        case .debug: .debug
        case .warn: .warn
        case .error: .error
        case .critical: .critical
        }
        DatadogInternal.consolePrint(message, coreLoggerLevel)
    }

    @objc
    public static func telemetryDebug(id: String, message: String) {
        Datadog._internal.telemetry.debug(id: id, message: message)
    }

    @objc
    public static func telemetryError(id: String, message: String, kind: String?, stack: String?) {
        Datadog._internal.telemetry.error(id: id, message: message, kind: kind, stack: stack)
    }
}

@objc
public enum DDCoreLoggerLevel: Int {
    case debug
    case warn
    case error
    case critical
}
