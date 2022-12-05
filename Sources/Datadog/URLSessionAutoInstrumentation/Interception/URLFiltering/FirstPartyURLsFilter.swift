/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Filters `URLs` which match the first party hosts given by the user.
internal struct FirstPartyURLsFilter {

    private let tracingHeaderTypesProvider: TracingHeaderTypesProvider

    internal init(hosts: FirstPartyHosts) {
        self.tracingHeaderTypesProvider = TracingHeaderTypesProvider(firstPartyHosts: hosts)
    }

    /// Returns `true` if given `URL` matches the first party hosts defined by the user; `false` otherwise.
    func isFirstParty(url: URL?) -> Bool {
        guard let host = url?.host, let url = URL(string: host) else {
            return false
        }
        return !tracingHeaderTypesProvider.tracingHeaderTypes(for: url).isEmpty
    }

    // Returns `true` if given `String` can be parsed as a URL and matches the first
    // party hosts defined by the user; `false` otherwise
    func isFirstParty(string: String) -> Bool {
        guard let url = URL(string: string) else {
            return false
        }
        return isFirstParty(url: url)
    }
}
