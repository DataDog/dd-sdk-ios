/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !canImport(MetricKit)

internal final class DatadogMetricSubscriber: NSObject {
    required init(core: DatadogCoreProtocol) {
        super.init()
    }
}

#else

import MetricKit

internal final class DatadogMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    weak var core: DatadogCoreProtocol?

    required init(core: DatadogCoreProtocol) {
        self.core = core
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    // Receive daily metrics.
    func didReceive(_ payloads: [MXMetricPayload]) {
       // Process metrics.
    }


    // Receive diagnostics immediately when available.
    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
       // Process diagnostics.
    }
}



extension DatadogMetricSubscriber {

    func record<UnitType>(name: String, _ measure: Measurement<UnitType>) {
        let timestamp = Date()
        core?.scope(for: MetricFeature.name)?.eventWriteContext { context, writer in
//            let value = Metric(
//                name: self.name,
//                type: self.type,
//                point: Serie.Point(
//                    timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                    value: value
//                ),
//                interval: self.interval,
//                unit: self.unit,
//                resources: self.resources,
//                tags: self.tags
//            )
//
//            writer.write(value: value)
        }
    }
}

#endif
