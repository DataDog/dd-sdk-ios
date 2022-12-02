/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct TracingHeaderTypesProvider {
    private let hostsWithHeaderTypes: Dictionary<String, Set<TracingHeaderType>>
    private let defaultValue: TracingHeaderType = .dd
    
    init(
        hostsWithHeaderTypes: Dictionary<String, Set<TracingHeaderType>>
    ) {
        self.hostsWithHeaderTypes = hostsWithHeaderTypes
    }

    func tracingHeaderTypes(for url: URL?) -> Set<TracingHeaderType> {
        for (key, value) in hostsWithHeaderTypes {
            let regex = "^(.*\\.)*[.]?\(NSRegularExpression.escapedPattern(for: key))$"
            if url?.absoluteString.range(of: regex, options: .regularExpression) != nil {
                return value
            }
        }
        return .init(arrayLiteral: defaultValue)
    }
}
