/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public protocol FlagsClientInternal: AnyObject {
    /// Note: This is an internal method. Expect breaking changes in the future.
    @_spi(Internal)
    func getAllFlagsDetails() -> [String: FlagDetails<AnyValue>]?

    /// Note: This is an internal method. Expect breaking changes in the future.
    @_spi(Internal)
    func trackEvaluation(key: String)
}

extension FlagsClientInternal {
    @_spi(Internal)
    public func getAllFlagsDetails() -> [String: FlagDetails<AnyValue>]? {
        // no-op
        return nil
    }

    @_spi(Internal)
    public func trackEvaluation(key: String) {
        // no-op
    }
}
