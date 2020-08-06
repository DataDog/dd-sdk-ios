/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/* Collection of mappings from SDK models to `RUMDataModel` format. */

internal extension RUMUUID {
    var toRUMDataFormat: String {
        return rawValue.uuidString.lowercased()
    }
}

internal extension RUMErrorSource {
    var toRUMDataFormat: RUMSource {
        switch self {
        case .source: return .source
        case .console: return .console
        case .network: return .network
        case .agent: return .agent
        case .logger: return .logger
        case .webview: return .webview
        }
    }
}

internal extension RUMUserActionType {
    /// TODO: RUMM-517 Map `RUMUserActionType` to enum cases from generated models
    var toRUMDataFormat: String {
        switch self {
        case .tap: return "tap"
        case .scroll: return "scroll"
        case .swipe: return "swipe"
        case .custom: return "custom"
        }
    }
}
