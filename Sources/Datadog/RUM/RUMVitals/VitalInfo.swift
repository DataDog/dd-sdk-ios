/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal typealias VitalPublisher = ValuePublisher<VitalInfo>

internal struct VitalInfo {
    /// Number of sample for this info
    var sampleCount: Int { Int(sampleCountDouble) }
    /// To avoid int->double conversion too often
    private var sampleCountDouble = 0.0
    /// Minimum value across all samples
    private(set) var minValue: Double?
    /// Maximum value across all samples
    private(set) var maxValue: Double?
    /// Average value across all samples
    private(set) var meanValue: Double?
    /// Diff between max and min values
    var greatestDiff: Double? {
        if let someMax = maxValue, let someMin = minValue {
            return someMax - someMin
        }
        return nil
    }

    mutating func addSample(_ sample: Double) {
        // Assuming M(n) is the mean value of the first n samples
        // M(n) = ∑ sample(n) / n
        // n⨉M(n) = ∑ sample(n)
        // M(n+1) = ∑ sample(n+1) / (n+1)
        //        = [ sample(n+1) + ∑ sample(n) ] / (n+1)
        //        = (sample(n+1) + n⨉M(n)) / (n+1)
        meanValue = (sample + (sampleCountDouble * (meanValue ?? 0.0))) / (sampleCountDouble + 1.0)
        // swiftlint:disable force_unwrapping
        minValue = minValue == nil ? sample : min(minValue!, sample)
        maxValue = maxValue == nil ? sample : max(maxValue!, sample)
        // swiftlint:enable force_unwrapping
        sampleCountDouble += 1.0
    }

    func scaledDown(by scaleFactor: Double) -> Self {
        if scaleFactor != 0.0,
           let min = minValue,
           let max = maxValue,
           let mean = meanValue {
            return VitalInfo(
                sampleCountDouble: sampleCountDouble,
                minValue: min / scaleFactor,
                maxValue: max / scaleFactor,
                meanValue: mean / scaleFactor
            )
        }
        return self
    }
    
    func asPerformanceMetric() -> PerformanceMetric {
        return PerformanceMetric(
            average: meanValue ?? 0.0,
            max: maxValue ?? 0.0,
            metricMax: nil,
            min: minValue ?? 0.0
        )
    }
}

internal struct PerformanceMetric: Codable {
    public let average: Double
    public let max: Double
    public let metricMax: Double?
    public let min: Double
    
    enum CodingKeys: String, CodingKey {
        case average = "average"
        case max = "max"
        case metricMax = "metric_max"
        case min = "min"
    }
}

