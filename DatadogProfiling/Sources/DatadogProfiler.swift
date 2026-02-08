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

internal final class DatadogProfiler: ProfilingWriter {
    private let isContinuousProfiling: Bool
    let telemetryController: ProfilingTelemetryController
    let featureScope: FeatureScope
    let operation: ProfilingOperation = .customProfiling

    private var profilingOperations: Set<String> = []

    init(
        core: DatadogCoreProtocol,
        isContinuousProfiling: Bool,
        telemetryController: ProfilingTelemetryController
    ) {
        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.isContinuousProfiling = isContinuousProfiling
        self.telemetryController = telemetryController

        print("*******************************init custom profiling \(Date())")
    }
}

extension DatadogProfiler: CustomProfiler {
    func start(
        name: String,
        operationKey: String?,
        currentThreadOnly: Bool,
        attributes: [DatadogInternal.AttributeKey : any DatadogInternal.AttributeValue],
        sampleRate: DatadogInternal.SampleRate
    ) {
        if Sampler(samplingRate: sampleRate).sample() {

            // attention I need to out this thread safe
            profilingOperations.insert("\(name),\(operationKey)")
            featureScope.send(
                message: .payload(
                    StartProfilingMessage(
                        name: name,
                        operationKey: operationKey,
                        attributes: attributes
                    )
                )
            )

            if isContinuousProfiling == false {
                profiler_start()
            }
        }
    }

    func stop(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        let profilingContext = ProfilingContext(status: .current)
        featureScope.set(context: profilingContext)

        profilingOperations.remove("\(name),\(operationKey)")

        guard profilingOperations.isEmpty else {
            // There are still profiling operations running
            return
        }

        if self.isContinuousProfiling == false {
            profiler_stop()
        }

        guard let profile = profiler_get_profile(true) else {
            print("+++++++++++++++no profile")
            return
        }

        writeProfilingEvent(with: profile, from: featureScope)

        // Notify SDK Features
        var failureReason: String?
        if case let .error(reason: reason) = profilingContext.status {
            failureReason = reason.rawValue
        }
        
        featureScope.send(
            message: .payload(
                StopProfilingMessage(
                    name: name,
                    operationKey: operationKey,
                    failureReason: failureReason,
                    attributes: attributes
                )
            )
        )
    }
}
