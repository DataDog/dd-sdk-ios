/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogProfiler

extension Array {
    func firstElement<T>(of type: T.Type = T.self) -> T? {
        return compactMap({ $0 as? T }).first
    }
}
