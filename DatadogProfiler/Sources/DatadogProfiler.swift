/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public enum Profiler {
    public struct Configuration {
        let apiKey: String

        public init(apiKey: String) {
            self.apiKey = apiKey
        }
    }

    public static func enable(with configuration: Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) {
        try! core.register(
            feature: ProfilerFeature(
                requestBuilder: RequestBuilder(
                    apiKey: configuration.apiKey,
                    telemetry: core.telemetry
                ),
                messageReceiver: NOPFeatureMessageReceiver())
        )
    }

    public static func start(currentThreadOnly: Bool = false, in core: DatadogCoreProtocol = CoreRegistry.default) {
        core.get(feature: ProfilerFeature.self)?
            .start(currentThreadOnly: currentThreadOnly)
    }

    public static func stop(in core: DatadogCoreProtocol = CoreRegistry.default) {
        guard
            let feature = core.get(feature: ProfilerFeature.self),
            let start = feature.startDate,
            let data = try? feature.stop()
        else {
            return
        }

        let end = Date()

        core.scope(for: ProfilerFeature.self).eventWriteContext { context, writer in
            var event = ProfileEvent(
                start: start,
                end: end,
                cpuProf: data,
                service: context.service,
                version: context.version
            )

            if let rum = context.additionalContext(ofType: RUMCoreContext.self) {
                event.applicationID = rum.applicationID
                event.sessionID = rum.sessionID
                event.viewID = rum.viewID
            }

            writer.write(value: event)
        }
    }
}
