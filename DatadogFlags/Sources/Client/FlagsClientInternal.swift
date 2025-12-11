/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public protocol FlagsClientInternal: AnyObject {
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func getFlagAssignmentsSnapshot() -> [String: FlagAssignment]?

    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func trackFlagSnapshotEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext)
}

extension FlagsClientInternal {
    @_spi(Internal)
    public func getFlagAssignmentsSnapshot() -> [String: FlagAssignment]? {
        // no-op
        return nil
    }

    @_spi(Internal)
    public func trackFlagSnapshotEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext) {
        // no-op
    }
}
