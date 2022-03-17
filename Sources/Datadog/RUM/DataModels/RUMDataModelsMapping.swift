/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/* Collection of mappings from various types to `RUMDataModel` format. */

extension BinaryInteger {
    var toInt64: Int64 {
        return Int64(clamping: self)
    }
}

internal extension RUMUUID {
    var toRUMDataFormat: String {
        return rawValue.uuidString.lowercased()
    }
}

internal extension RUMInternalErrorSource {
    var toRUMDataFormat: RUMErrorEvent.Error.Source {
        switch self {
        case .custom: return .custom
        case .source: return .source
        case .network: return .network
        case .webview: return .webview
        case .console: return .console
        case .logger: return .logger
        }
    }
}

internal extension RUMUserActionType {
    var toRUMDataFormat: RUMActionEvent.Action.ActionType {
        switch self {
        case .tap: return .tap
        case .click: return .click
        case .scroll: return .scroll
        case .swipe: return .swipe
        case .custom: return .custom
        }
    }
}
