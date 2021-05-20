/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides interface for observing Vital info from a producer
internal class VitalObserver: ValueObserver {
    let listener: VitalListener

    private var vitalInfo = VitalInfo(
        sampleCount: 0,
        minValue: Double.greatestFiniteMagnitude,
        maxValue: -Double.greatestFiniteMagnitude,
        meanValue: 0.0
    )

    init(listener: VitalListener) {
        self.listener = listener
    }

    // MARK: - ValueObserver
    final func onValueChanged(oldValue: Double, newValue: Double) {
        let newSampleCount = vitalInfo.sampleCount + 1
        // Assuming M(n) is the mean value of the first n samples
        // M(n) = ∑ sample(n) / n
        // n⨉M(n) = ∑ sample(n)
        // M(n+1) = ∑ sample(n+1) / (n+1)
        //        = [ sample(n+1) + ∑ sample(n) ] / (n+1)
        //        = (sample(n+1) + n⨉M(n)) / (n+1)
        let newMeanValue = (newValue + (Double(vitalInfo.sampleCount) * vitalInfo.meanValue)) / Double(newSampleCount)
        let newVitalInfo = VitalInfo(
            sampleCount: newSampleCount,
            minValue: min(vitalInfo.minValue, newValue),
            maxValue: max(vitalInfo.maxValue, newValue),
            meanValue: newMeanValue
        )
        vitalInfo = newVitalInfo
        listener.onVitalInfo(info: newVitalInfo)
    }
}
