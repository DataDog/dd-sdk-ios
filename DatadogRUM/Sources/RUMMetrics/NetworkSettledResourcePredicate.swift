/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A struct representing the parameters of a resource that may be considered for the Time-to-Network-Settled (TNS) metric.
public struct TNSResourceParams {
    /// The URL of the resource.
    public let url: String

    /// The time elapsed from when the view started to when the resource started.
    public let timeSinceViewStart: TimeInterval

    /// The name of the view in which the resource is tracked.
    public let viewName: String
}

/// A protocol for classifying network resources for the Time-to-Network-Settled (TNS) metric.
/// Implement this protocol to customize the logic for determining which resources are included in the TNS calculation.
///
/// **Note:**
/// - The `isInitialResource(from:)` method will be called on a secondary thread.
/// - The implementation must not assume any threading behavior and should avoid blocking the thread.
/// - The method should always return the same result for the same input parameters to ensure consistency in TNS calculation.
public protocol NetworkSettledResourcePredicate {
    /// Determines if the provided resource should be included in the TNS metric calculation.
    ///
    /// - Parameter resourceParams: The parameters of the resource.
    /// - Returns: `true` if the resource qualifies for TNS metric calculation, `false` otherwise.
    func isInitialResource(from resourceParams: TNSResourceParams) -> Bool
}

/// A predicate implementation for classifying Time-to-Network-Settled (TNS) resources based on a time threshold.
/// It will calculate TNS using all resources that start within the specified threshold after the view starts.
///
/// The default value of the threshold is 0.1s.
public struct TimeBasedTNSResourcePredicate: NetworkSettledResourcePredicate {
    /// The default value of the threshold.
    public static let defaultThreshold: TimeInterval = 0.1

    /// The time threshold (in seconds) used to classify a resource.
    let threshold: TimeInterval

    /// Initializes a new predicate with a specified time threshold.
    ///
    /// - Parameter threshold: The time threshold (in seconds) used to classify resources. The default value is 0.1 seconds.
    public init(threshold: TimeInterval = TimeBasedTNSResourcePredicate.defaultThreshold) {
        self.threshold = threshold
    }

    /// Determines if the provided resource should be included in the TNS metric calculation.
    /// A resource is included if it starts within the specified threshold from the view start time.
    ///
    /// - Parameter resourceParams: The parameters of the resource.
    /// - Returns: `true` if the resource qualifies for TNS metric calculation, `false` otherwise.
    public func isInitialResource(from resourceParams: TNSResourceParams) -> Bool {
        return resourceParams.timeSinceViewStart <= threshold
    }
}
