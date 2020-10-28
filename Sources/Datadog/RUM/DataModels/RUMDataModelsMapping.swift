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

internal extension RUMHTTPMethod {
    var toRUMDataFormat: RUMDataMethod {
        switch self {
        case .GET: return .methodGET
        case .POST: return .post
        case .PUT: return .put
        case .DELETE: return .delete
        case .HEAD: return .head
        case .PATCH: return .patch
        }
    }
}

internal extension RUMResourceKind {
    var toRUMDataFormat: RUMDataResourceType {
        switch self {
        case .image: return .image
        case .xhr: return .xhr
        case .beacon: return .beacon
        case .css: return .css
        case .document: return .document
        case .fetch: return .fetch
        case .font: return .font
        case .js: return .js
        case .media: return .media
        case .other: return .other
        }
    }
}

internal extension RUMErrorSource {
    var toRUMDataFormat: RUMDataSource {
        switch self {
        case .custom: return .custom
        case .source: return .source
        case .network: return .network
        case .webview: return .webview
        }
    }
}

internal extension RUMUserActionType {
    var toRUMDataFormat: RUMDataActionType {
        switch self {
        case .tap: return .tap
        case .scroll: return .scroll
        case .swipe: return .swipe
        case .custom: return .custom
        }
    }
}
