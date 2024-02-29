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
        for payload in payloads {
            let timestamp = Date() // payload.timeStampEnd
            if let cpuMetrics = payload.cpuMetrics {
                record(name: "cumulativeCPUTime", timestamp: timestamp, cpuMetrics.cumulativeCPUTime)

                if #available(iOS 14.0, *) {
                    record(name: "cumulativeCPUInstructions", timestamp: timestamp, cpuMetrics.cumulativeCPUInstructions)
                }
            }

            if let gpuMetrics = payload.gpuMetrics {
                record(name: "cumulativeGPUTime", timestamp: timestamp, gpuMetrics.cumulativeGPUTime)
            }

            if let applicationTimeMetrics = payload.applicationTimeMetrics {
                record(name: "cumulativeForegroundTime", timestamp: timestamp, applicationTimeMetrics.cumulativeForegroundTime)
                record(name: "cumulativeBackgroundTime", timestamp: timestamp, applicationTimeMetrics.cumulativeBackgroundTime)
                record(name: "cumulativeBackgroundAudioTime", timestamp: timestamp, applicationTimeMetrics.cumulativeBackgroundAudioTime)
                record(name: "cumulativeBackgroundLocationTime", timestamp: timestamp, applicationTimeMetrics.cumulativeBackgroundLocationTime)
            }

            if let locationActivityMetrics = payload.locationActivityMetrics {
                record(name: "cumulativeBestAccuracyTime", timestamp: timestamp, locationActivityMetrics.cumulativeBestAccuracyTime)
                record(name: "cumulativeBestAccuracyForNavigationTime", timestamp: timestamp, locationActivityMetrics.cumulativeBestAccuracyForNavigationTime)
                record(name: "cumulativeNearestTenMetersAccuracyTime", timestamp: timestamp, locationActivityMetrics.cumulativeNearestTenMetersAccuracyTime)
                record(name: "cumulativeHundredMetersAccuracyTime", timestamp: timestamp, locationActivityMetrics.cumulativeHundredMetersAccuracyTime)
                record(name: "cumulativeKilometerAccuracyTime", timestamp: timestamp, locationActivityMetrics.cumulativeKilometerAccuracyTime)
                record(name: "cumulativeThreeKilometersAccuracyTime", timestamp: timestamp, locationActivityMetrics.cumulativeThreeKilometersAccuracyTime)
            }

            if let networkTransferMetrics = payload.networkTransferMetrics {
                record(name: "cumulativeWifiUpload", timestamp: timestamp, networkTransferMetrics.cumulativeWifiUpload)
                record(name: "cumulativeWifiDownload", timestamp: timestamp, networkTransferMetrics.cumulativeWifiDownload)
                record(name: "cumulativeCellularUpload", timestamp: timestamp, networkTransferMetrics.cumulativeCellularUpload)
                record(name: "cumulativeCellularDownload", timestamp: timestamp, networkTransferMetrics.cumulativeCellularDownload)
            }

            if let diskIOMetrics = payload.diskIOMetrics {
                record(name: "cumulativeLogicalWrites", timestamp: timestamp, diskIOMetrics.cumulativeLogicalWrites)
            }

            if let memoryMetrics = payload.memoryMetrics {
                record(name: "peakMemoryUsage", timestamp: timestamp, memoryMetrics.peakMemoryUsage)
                // add averageSuspendedMemory
            }

//            if let displayMetrics = payload.displayMetrics {
//                // add averagePixelLuminance
//            }

            if #available(iOS 14.0, *), let animationMetrics = payload.animationMetrics {
                record(name: "scrollHitchTimeRatio", timestamp: timestamp, animationMetrics.scrollHitchTimeRatio)
            }
        }
    }


    // Receive diagnostics immediately when available.
    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
       // Process diagnostics.
    }
}

extension DatadogMetricSubscriber {

    func record<UnitType>(name: String, timestamp: Date, _ measure: Measurement<UnitType>
    ) {
        core?.scope(for: MetricFeature.name)?.eventWriteContext { context, writer in
            let submission = Submission(
                metadata: Submission.Metadata(
                    name: "\(context.source).\(context.applicationBundleIdentifier).\(name)",
                    type: .gauge,
                    interval: nil,
                    unit: measure.unit.symbol,
                    resources: [],
                    tags: [
                        "service:\(context.service)",
                        "env:\(context.env)",
                        "version:\(context.version)",
                        "build_number:\(context.buildNumber)",
                        "source:\(context.source)",
                        "application_name:\(context.applicationName)",
                    ]
                ),
                point: Serie.Point(
                    timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
                    value: measure.value
                )
            )

            writer.write(value: submission)
        }
    }
}

#endif
