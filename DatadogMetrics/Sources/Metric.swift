/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The type of metric. The available types are 0 (unspecified), 1 (count), 2 (rate), and 3 (gauge). Allowed enum values: 0,1,2,3
enum MetricType: Int, Codable {
    case unspecified = 0
    case count = 1
    case rate = 2
    case gauge = 3
}

internal struct Serie: Codable {
    struct Point: Codable {
        let timestamp: Int64
        let value: Double
    }

    struct Resource: Codable {
        let name: String
        let type: String
    }

    let type: MetricType
    let interval: Int64?
    let metric: String
    let unit: String?
    let points: [Point]
    let resources: [Resource]
    let tags: [String]
}

enum SubmissionType: Int, Codable {
    case count
    case gauge
    case histogram
}

internal struct Submission: Codable {
    struct Metadata: Codable {
        let name: String
        let type: SubmissionType
        let interval: Int64?
        let unit: String?
        let resources: [Serie.Resource]
        let tags: [String]
    }

    let metadata: Metadata
    let point: Serie.Point
}

extension Submission.Metadata: Hashable {
    /// Hashes the essential components of this value by feeding them into the
    /// given hasher.
    ///
    /// Implement this method to conform to the `Hashable` protocol. The
    /// components used for hashing must be the same as the components compared
    /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
    /// with each of these components.
    ///
    /// - Important: In your implementation of `hash(into:)`,
    ///   don't call `finalize()` on the `hasher` instance provided,
    ///   or replace it with a different instance.
    ///   Doing so may become a compile-time error in the future.
    ///
    /// - Parameter hasher: The hasher to use when combining the components
    ///   of this instance.
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type
    }
}
