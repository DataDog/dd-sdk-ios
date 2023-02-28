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
    struct Constants {
        // We use normalized 0...60 range for refresh rate in Mobile Vitals,
        // assuming 60 is the industry standard.
        static let normalizedRefreshRate = 60.0
    }

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
        let info = refreshRatePublisher.currentValue
        return info.scaledDown(by: maximumRefreshRate / Constants.normalizedRefreshRate)
    }

    private var timer: Timer?

    init(
        cpuReader: SamplingBasedVitalReader,
        memoryReader: SamplingBasedVitalReader,
        refreshRateReader: ContinuousVitalReader,
        frequency: TimeInterval,
        maximumRefreshRate: Double = Double(UIScreen.main.maximumFramesPerSecond)
    ) {
        self.cpuReader = cpuReader

        self.memoryReader = memoryReader

        self.refreshRateReader = refreshRateReader
        self.refreshRateReader.register(self.refreshRatePublisher)
        self.maximumRefreshRate = maximumRefreshRate

        // Take initial sample
        RunLoop.main.perform { [weak self] in
            self?.takeSample()
        }
        // Schedule reoccuring samples
        let timer = Timer(
            timeInterval: frequency,
            repeats: true
        ) { [weak self] _ in
            self?.takeSample()
        }
        // NOTE: RUMM-1280 based on my running Example app
        // non-main run loops don't fire the timer.
        // Although i can't catch this in unit tests
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
