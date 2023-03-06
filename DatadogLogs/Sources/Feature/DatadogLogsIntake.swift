/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public enum DatadogLogsIntake {
    case datadog
    case custom(URL)
}

extension DatadogLogsIntake {
    func url(with context: DatadogContext) -> URL {
        switch self {
        case .datadog:
            return context.site.endpoint.appendingPathComponent("api/v2/logs")
        case .custom(let url):
            return url
        }
    }
}
