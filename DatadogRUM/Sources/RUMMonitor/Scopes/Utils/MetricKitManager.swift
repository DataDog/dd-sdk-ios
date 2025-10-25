/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !canImport(MetricKit)

internal final class MetricKitManager: NSObject {
    required init(core: DatadogCoreProtocol) {
        super.init()
    }
}

#else

import MetricKit

internal final class MetricKitManager: NSObject, MXMetricManagerSubscriber {
    @ReadWriteLock
    private(set) var attributes: [AttributeKey: AttributeValue] = [:]

    private var receivedPayloads: Bool = false
    private var receivedDiagnostics: Bool = false

    override required init() {
        super.init()
        if #available(iOS 13.0, *) {
            MXMetricManager.shared.add(self)
        }
    }

    func stop() {
        guard #available(iOS 13.0, *) else {
            return
        }
        if receivedPayloads && receivedDiagnostics {
            MXMetricManager.shared.remove(self)
        }
    }

    // Receive daily metrics.
    @available(iOS 13.0, *)
    func didReceive(_ payloads: [MXMetricPayload]) {
        for (index, payload) in payloads.enumerated() {
            let timeStampBegin = payload.timeStampBegin
            let timeStampEnd = payload.timeStampEnd

            if let applicationLaunchMetrics = payload.applicationLaunchMetrics {
                attributes["metric_kit_application_launch (\(index))"] = """
                        Begin Date: \(shortFormatter.string(from: timeStampBegin))
                        End Date: \(shortFormatter.string(from: timeStampEnd))
                        Payload: \(applicationLaunchMetrics.dictionaryRepresentation())
                        """
            }
        }
        receivedPayloads = true
        stop()
    }

    // Receive diagnostics immediately when available (iOS 15 and above).
    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for (index, payload) in payloads.enumerated() {
            let timeStampBegin = payload.timeStampBegin
            let timeStampEnd = payload.timeStampEnd

            if #available(iOS 16.0, *), payload.appLaunchDiagnostics != nil {
                attributes["metric_kit_diagnostics (\(index))"] = """
                                    Begin Date: \(shortFormatter.string(from: timeStampBegin))
                                    End Date: \(shortFormatter.string(from: timeStampEnd))
                                    Payload: \(payload.dictionaryRepresentation())
                                    """
            }

            if payload.crashDiagnostics != nil,
               attributes["metric_kit_crash_diagnostics (\(index))"] == nil {
                attributes["metric_kit_crash_diagnostics (\(index))"] = """
                                Begin Date: \(shortFormatter.string(from: timeStampBegin))
                                End Date: \(shortFormatter.string(from: timeStampEnd))
                                Payload: \(payload.dictionaryRepresentation())
                                """
            }
        }
        receivedDiagnostics = true
        stop()
    }
}

#endif
