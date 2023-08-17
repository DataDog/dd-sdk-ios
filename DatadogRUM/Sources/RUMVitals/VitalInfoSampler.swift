/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import class UIKit.UIScreen

internal protocol SamplingBasedVitalReader {
    func readVitalData() -> Double?
}

internal protocol ContinuousVitalReader {
    func register(_ valuePublisher: VitalPublisher)
    func unregister(_ valuePublisher: VitalPublisher)
}

internal final class VitalInfoSampler {
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
    private let maximumRefreshRate: Double

    var refreshRate: VitalInfo {
        return refreshRatePublisher.currentValue
    }

    private var timer: Timer?

    private static var maximumFramesPerSecond: Double {
        get {
#if os(visionOS)
            return 120.0
#else
            return Double(UIScreen.main.maximumFramesPerSecond)
#endif
        }
    }

    init(
        cpuReader: SamplingBasedVitalReader,
        memoryReader: SamplingBasedVitalReader,
        refreshRateReader: ContinuousVitalReader,
        frequency: TimeInterval,
        maximumRefreshRate: Double = VitalInfoSampler.maximumFramesPerSecond
    ) {
        self.cpuReader = cpuReader

        self.memoryReader = memoryReader

        self.refreshRateReader = refreshRateReader
        self.refreshRateReader.register(self.refreshRatePublisher)
        self.maximumRefreshRate = maximumRefreshRate

        // Take initial sample
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            self?.takeSample()
        }
        // Schedule reoccuring samples
        let timer = Timer(
            timeInterval: frequency,
            repeats: true
        ) { [weak self] _ in
            self?.takeSample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
        refreshRateReader.unregister(refreshRatePublisher)
    }

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
