/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct TracingHeaderTypesProvider {
    private let firstPartyHosts: FirstPartyHosts

    init(
        firstPartyHosts: FirstPartyHosts
    ) {
        self.firstPartyHosts = firstPartyHosts
    }

    func tracingHeaderTypes(for url: URL?) -> Set<TracingHeaderType> {
        return firstPartyHosts.compactMap { item -> Set<TracingHeaderType>? in
            let regex = "^(.*\\.)*\(NSRegularExpression.escapedPattern(for: item.key))$"
            if url?.host?.range(of: regex, options: .regularExpression) != nil {
                return item.value
            }
            if url?.absoluteString.range(of: regex, options: .regularExpression) != nil {
                return item.value
            }
            return nil
        }
        .reduce(into: Set(), { partialResult, value in
            partialResult.formUnion(value)
        })
    }
}
