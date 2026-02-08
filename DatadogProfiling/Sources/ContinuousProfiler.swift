/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class ContinuousProfiler: FeatureMessageReceiver {
    let telemetryController: ProfilingTelemetryController
    let featureScope: FeatureScope
    let operation: ProfilingOperation = .continuousProfiling

    private let profilingConditions: ProfilingConditions
    private var timer: Timer?

    init(
        core: DatadogCoreProtocol,
        telemetryController: ProfilingTelemetryController = .init(),
        profilingConditions: ProfilingConditions = .init(),
        frequency: TimeInterval = TimeInterval(30)
    ) {
        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.telemetryController = telemetryController
        self.profilingConditions = profilingConditions

        print("*******************************init continuous profiling \(Date())")

        // Schedule reoccurring samples
        let timer = Timer(
            timeInterval: frequency,
            repeats: true
        ) { [weak self] _ in

            self?.sendProfile()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(cmd as TTIDMessage) = message else {
            return false
        }

        return false
    }
}

extension ContinuousProfiler: ProfilingWriter {

    func sendProfile() {
        print("*******************************handling continuous profiling \(Date())")

        featureScope.context { context in
            let profilingContext = ProfilingContext(status: .current)
            self.featureScope.set(context: profilingContext)

            let canProfile = self.profilingConditions.canProfileApplication(with: context)

            switch profilingContext.status {
            case .stopped:
                if canProfile {
                    profiler_start()
                }
            case .running:
                if canProfile == false {
                    profiler_stop()
                }

                guard let profile = profiler_get_profile(true) else {
                    print("+++++++++++++++no profile")
                    return
                }

                self.writeProfilingEvent(with: profile, from: self.featureScope)
            default: break
            }
        }
    }
}
