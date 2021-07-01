/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol SamplingBasedVitalReader {
    func readVitalData() -> Double?
}

internal protocol ContinuousVitalReader {
    func register(_ valuePublisher: VitalPublisher)
    func unregister(_ valuePublisher: VitalPublisher)
}

internal final class VitalInfoSampler {
    private static let frequency: TimeInterval = 1.0

    let cpuReader: SamplingBasedVitalReader
    private let cpuPublisher = VitalPublisher(initialValue: VitalInfo())

    var cpu: VitalInfo {
        return cpuPublisher.currentValue
    }

    let memoryReader: SamplingBasedVitalReader
    private let memoryPublisher = VitalPublisher(initialValue: VitalInfo())

    var memory: VitalInfo {
        return memoryPublisher.currentValue
    }

    let refreshRateReader: ContinuousVitalReader
    private let refreshRatePublisher = VitalPublisher(initialValue: VitalInfo())

    var refreshRate: VitalInfo {
        return refreshRatePublisher.currentValue
    }

    private var timer: Timer?

    init(
        cpuReader: SamplingBasedVitalReader,
        memoryReader: SamplingBasedVitalReader,
        refreshRateReader: ContinuousVitalReader,
        frequency: TimeInterval = VitalInfoSampler.frequency
    ) {
        self.cpuReader = cpuReader
        self.memoryReader = memoryReader
        self.refreshRateReader = refreshRateReader
        self.refreshRateReader.register(self.refreshRatePublisher)

        takeSample()
        let timer = Timer.scheduledTimer(
            timeInterval: frequency,
            target: self,
            selector: #selector(takeSample),
            userInfo: nil,
            repeats: true
        )
        self.timer = timer
    }

    deinit {
        self.timer?.invalidate()
    }

    @objc
    private func takeSample() {
        if let newCPUSample = cpuReader.readVitalData() {
            cpuPublisher.mutateAsync { cpuInfo in
                cpuInfo.addSample(newCPUSample)
            }
        }
        if let newMemorySample = memoryReader.readVitalData() {
            memoryPublisher.mutateAsync { memoryInfo in
                memoryInfo.addSample(newMemorySample)
            }
        }
    }
}
