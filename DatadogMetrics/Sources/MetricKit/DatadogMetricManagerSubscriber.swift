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

            if let cellularConditionMetrics = payload.cellularConditionMetrics {
                record(name: "cellularConditionTime", timestamp: timestamp, cellularConditionMetrics.histogrammedCellularConditionTime)
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

            if let applicationLaunchMetrics = payload.applicationLaunchMetrics {
                record(name: "timeToFirstDraw", timestamp: timestamp, applicationLaunchMetrics.histogrammedTimeToFirstDraw)
                record(name: "applicationResumeTime", timestamp: timestamp, applicationLaunchMetrics.histogrammedApplicationResumeTime)

                if #available(iOS 15.2, *) {
                    record(name: "optimizedTimeToFirstDraw", timestamp: timestamp, applicationLaunchMetrics.histogrammedOptimizedTimeToFirstDraw)
                }

                if #available(iOS 16.0, *) {
                    record(name: "extendedLaunch", timestamp: timestamp, applicationLaunchMetrics.histogrammedExtendedLaunch)
                }
            }

            if let applicationResponsivenessMetrics = payload.applicationResponsivenessMetrics {
                record(name: "applicationHangTime", timestamp: timestamp, applicationResponsivenessMetrics.histogrammedApplicationHangTime)
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

    func record<UnitType>(name: String, timestamp: Date, _ measure: Measurement<UnitType>) {
        core?.scope(for: MetricFeature.name)?.eventWriteContext { context, writer in
            let serie = Serie(
                type: .gauge,
                interval: nil,
                metric: "\(context.source).\(context.applicationBundleIdentifier).\(name)",
                unit: measure.unit.symbol,
                points: [
                    Serie.Point(
                        timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
                        value: measure.value
                    )
                ],
                resources: [],
                tags: [
                    "service:\(context.service)",
                    "env:\(context.env)",
                    "version:\(context.version)",
                    "build_number:\(context.buildNumber)",
                    "source:\(context.source)",
                    "application_name:\(context.applicationName)",
                ]
            )

            writer.write(value: MetricMessage.serie(serie))
        }
    }

    func record<UnitType>(name: String, timestamp: Date, _ histogram: MXHistogram<UnitType>) {
        core?.scope(for: MetricFeature.name)?.eventWriteContext { context, writer in
            let metric = "\(context.source).\(context.applicationBundleIdentifier).\(name)"
            let tags = [
                "service:\(context.service)",
                "env:\(context.env)",
                "version:\(context.version)",
                "build_number:\(context.buildNumber)",
                "source:\(context.source)",
                "application_name:\(context.applicationName)",
            ]

            let enumarator = histogram.bucketEnumerator
            while let bucket = enumarator.nextObject() as? MXHistogramBucket<UnitType> {
                let min = Serie(
                    type: .gauge,
                    interval: nil,
                    metric: "\(metric).min",
                    unit: bucket.bucketStart.unit.symbol,
                    points: [
                        Serie.Point(
                            timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
                            value: bucket.bucketStart.value
                        )
                    ],
                    resources: [],
                    tags: tags
                )

                let max = Serie(
                    type: .gauge,
                    interval: nil,
                    metric: "\(metric).max",
                    unit: bucket.bucketEnd.unit.symbol,
                    points: [
                        Serie.Point(
                            timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
                            value: bucket.bucketEnd.value
                        )
                    ],
                    resources: [],
                    tags: tags
                )

                let bucketCount = Double(bucket.bucketCount)
                let count = Serie(
                    type: .count,
                    interval: nil,
                    metric: "\(metric).count",
                    unit: nil,
                    points: [
                        Serie.Point(
                            timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
                            value: bucketCount
                        )
                    ],
                    resources: [],
                    tags: tags
                )

//                // Just a guess, not a good one
//                let bucketAverage = (bucket.bucketEnd + bucket.bucketStart) / 2
//                let avg = Serie(
//                    type: .gauge,
//                    interval: nil,
//                    metric: "\(metric).avg",
//                    unit: bucketAverage.unit.symbol,
//                    points: [
//                        Serie.Point(
//                            timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                            value: bucketAverage.value
//                        )
//                    ],
//                    resources: [],
//                    tags: tags
//                )
//
//                let bucketSum = bucketAverage * bucketCount
//                let sum = Serie(
//                    type: .gauge,
//                    interval: nil,
//                    metric: "\(metric).sum",
//                    unit: bucketSum.unit.symbol,
//                    points: [
//                        Serie.Point(
//                            timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                            value: bucketSum.value
//                        )
//                    ],
//                    resources: [],
//                    tags: tags
//                )

                writer.write(value: MetricMessage.serie(min))
                writer.write(value: MetricMessage.serie(max))
                writer.write(value: MetricMessage.serie(count))
//                writer.write(value: MetricMessage.serie(avg))
//                writer.write(value: MetricMessage.serie(sum))
            }
        }
    }
}

#endif
