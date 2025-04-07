/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Returns the name of current module.
/// - Returns: The name of caller module.
public func moduleName(file: String = #fileID) -> String {
    guard let url = URL(string: file) else {
        return "unknown"
    }
    return url.pathComponents.first ?? "unknown"
}
