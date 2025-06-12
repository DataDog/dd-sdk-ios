/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Context describing Session Replay recording state.
public enum SessionReplayCoreContext {
    /// Boolean `has_replay` context.
    public struct HasReplay: AdditionalContext {
        public static let key = "has_replay"

        /// The `has_replay` value
        public let value: Bool

        /// Creates a Context value.
        ///
        /// - Parameter value: The `has_replay` value
        public init(value: Bool) {
            self.value = value
        }
    }

    /// Count of records per RUM View ID.
    public struct RecordsCount: AdditionalContext {
        public static let key = "sr_records_count_by_view_id"

        /// The `sr_records_count_by_view_id` value
        public let value: [String: Int64]

        /// Creates a Context value.
        ///
        /// - Parameter value: The `sr_records_count_by_view_id` value
        public init(value: [String: Int64]) {
            self.value = value
        }
    }
}
