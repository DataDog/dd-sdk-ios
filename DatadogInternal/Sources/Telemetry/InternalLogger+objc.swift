/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@objc(DDInternalLogger)
@objcMembers
@_spi(objc)
public class objc_InternalLogger: NSObject {
    /// Function printing `String` content to console. Intended to be used only by SDK components.
    @objc
    public static func consolePrint(_ message: String, _ level: objc_CoreLoggerLevel) {
        let coreLoggerLevel: CoreLoggerLevel = switch level {
        case .none: .debug
        case .debug: .debug
        case .warn: .warn
        case .error: .error
        case .critical: .critical
        }
        DatadogInternal.consolePrint(message, coreLoggerLevel)
    }

    @objc
    public static func telemetryDebug(id: String, message: String) {
        CoreRegistry.default.telemetry.debug(id: id, message: message)
    }

    @objc
    public static func telemetryError(id: String, message: String, kind: String?, stack: String?) {
        CoreRegistry.default.telemetry.error(id: id, message: message, kind: kind ?? "", stack: stack ?? "")
    }
}
