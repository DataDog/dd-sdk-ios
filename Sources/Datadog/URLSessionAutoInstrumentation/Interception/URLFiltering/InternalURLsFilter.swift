/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Filters `URLs` which match the first party hosts given by the user.
internal struct InternalURLsFilter {
    private let internalURLPrefixes: Set<String>

    init(urls: Set<String>) {
        self.internalURLPrefixes = urls
    }

    /// Returns `true` if given `URL` is an internal `URL` used by the SDK; `false` otherwise.
    func isInternal(url: URL?) -> Bool {
        guard let absoluteString = url?.absoluteString else {
            return false
        }
        return internalURLPrefixes.contains { internalURLPrefix in
            absoluteString.hasPrefix(internalURLPrefix)
        }
    }
}
