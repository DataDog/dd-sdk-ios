/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !canImport(MetricKit)

public final class DatadogMetricSubscriber: NSObject {
    required init(core: DatadogCoreProtocol) {
        super.init()
    }
}

#else

import MetricKit

public protocol SignpostController {

    func startMXMetric(for screen: StaticString)
    func stopMXMetric(for screen: StaticString)
}

@available(iOS 13.0, *)
extension OSLog {

    public static var fetchItems = MXMetricManager.makeLogHandle(category: "Dashboard")
    public static var screenDuration = MXMetricManager.makeLogHandle(category: "Screen")
    public static var screenEvent = MXMetricManager.makeLogHandle(category: "Event")
}

@available(iOS 13.0, *)
extension SignpostController {

    public func startMXMetric(for screen: StaticString) {

        mxSignpost(.begin, log: .screenDuration, name: screen, #file, ["param simao"])
    }
 
    public func stopMXMetric(for screen: StaticString) {

        mxSignpost(.end, log: .screenDuration, name: screen, #file, ["param simao end", "plus one"])
    }
}

@available(iOS 13.0, *)
public final class DatadogMetricSubscriber: NSObject, MXMetricManagerSubscriber, SignpostController {
    weak var core: DatadogCoreProtocol?

    var  diagnosticsString = ""

    public required init(core: DatadogCoreProtocol) {
        self.core = core
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    // Receive daily metrics.
    public func didReceive(_ payloads: [MXMetricPayload]) {

        UserDefaults.standard.set(Date(), forKey: "lastMetricKitReport")
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "numOfReports") + 1, forKey: "numOfReports")

        for payload in payloads {
            let timestamp = Date() // payload.timeStampEnd

            let data = payload.jsonRepresentation()

            print("\(payload.timeStampBegin)\(payload.timeStampEnd)")
            print("Payload: \(String(decoding: data, as: UTF8.self))\n")

            if let signpostMetrics = payload.signpostMetrics {
                record(name: "signpostMetrics", timestamp: timestamp, signpostMetrics)
            }

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

    // Receive diagnostics immediately when available (iOS 15 and above).
    @available(iOS 14.0, *)
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {

        UserDefaults.standard.set(Date(), forKey: "lastDiagnosticReport")
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "numOfDiagnostics") + 1, forKey: "numOfDiagnostics")

        var body = ""
        payloads.forEach { payload in
            let data = payload.jsonRepresentation()

            print("\(payload.timeStampBegin)\(payload.timeStampEnd)")

            body.append("\(String(decoding: data, as: UTF8.self))\n")
        }

        print("Payload: \(body)\n")
        print("--------------------------------------------------------")

        diagnosticsString = body
    }
}

@available(iOS 13.0, *)
extension DatadogMetricSubscriber {

    func record(name: String, timestamp: Date, _ signpostMetrics: [MXSignpostMetric]) {

        signpostMetrics.forEach { signpostMetric in

            guard signpostMetric.signpostCategory == "Screen" else {

                print(signpostMetric.signpostCategory)
                return
            }

            print("[signpostName]\(signpostMetric.signpostName): \(signpostMetric.totalCount)")

            if let signpostIntervalData = signpostMetric.signpostIntervalData {

                record(name: "histogrammedSignpostDuration", signpostName: signpostMetric.signpostName, timestamp: timestamp, signpostIntervalData.histogrammedSignpostDuration)

                if let cumulativeCPUTime = signpostIntervalData.cumulativeCPUTime {
                    record(name: "cumulativeCPUTime", signpostName: signpostMetric.signpostName, timestamp: timestamp, cumulativeCPUTime)
                }

                if let averageMemory = signpostIntervalData.averageMemory {
                    record(name: "averageMemory", signpostName: signpostMetric.signpostName, timestamp: timestamp, averageMemory)
                }

                if #available(iOS 15.0, *),
                   let cumulativeHitchTimeRatio = signpostIntervalData.cumulativeHitchTimeRatio {
                        record(name: "cumulativeHitchTimeRatio", signpostName: signpostMetric.signpostName, timestamp: timestamp, cumulativeHitchTimeRatio)
                }

                if let cumulativeLogicalWrites = signpostIntervalData.cumulativeLogicalWrites {
                    record(name: "cumulativeLogicalWrites", signpostName: signpostMetric.signpostName, timestamp: timestamp, cumulativeLogicalWrites)
                }
            }
        }
    }

    func record<UnitType>(name: String, timestamp: Date, _ measure: MXAverage<UnitType>) {
        record(name: name, signpostName: "overall", timestamp: timestamp, measure.averageMeasurement)
    }

    func record<UnitType>(name: String, signpostName: String?, timestamp: Date, _ measure: MXAverage<UnitType>) {
        record(name: name, signpostName: signpostName, timestamp: timestamp, measure.averageMeasurement)
    }

    func record<UnitType>(name: String, timestamp: Date, _ measure: Measurement<UnitType>) {
        record(name: name, signpostName: "overall", timestamp: timestamp, measure)
    }

    func record<UnitType>(name: String, signpostName: String?, timestamp: Date, _ measure: Measurement<UnitType>) {
//        core?.scope(for: MetricFeature.self).eventWriteContext { context, writer in
//
//            let tags = [
//                "service:\(context.service)",
//                "env:\(context.env)",
//                "version:\(context.version)",
//                "build_number:\(context.buildNumber)",
//                "source:\(context.source)",
//                "application_name:\(context.applicationName)",
//                "signpostName:\(signpostName)"
//            ]
//
//            let serie = Serie(
//                type: .gauge,
//                interval: nil,
//                metric: "\(context.source).\(context.applicationBundleIdentifier).\(name)",
//                unit: measure.unit.symbol,
//                points: [
//                    Serie.Point(
//                        timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                        value: measure.value
//                    )
//                ],
//                resources: [],
//                tags: tags
//            )
//
//            writer.write(value: MetricMessage.serie(serie))
//        }
    }

    func record<UnitType>(name: String, timestamp: Date, _ histogram: MXHistogram<UnitType>) {
        record(name: name, signpostName: "overall", timestamp: timestamp, histogram)
    }

    func record<UnitType>(name: String, signpostName: String?, timestamp: Date, _ histogram: MXHistogram<UnitType>) {
//        core?.scope(for: MetricFeature.self).eventWriteContext { context, writer in
//            let metric = "\(context.source).\(context.applicationBundleIdentifier).\(name)"
//            let tags = [
//                "service:\(context.service)",
//                "env:\(context.env)",
//                "version:\(context.version)",
//                "build_number:\(context.buildNumber)",
//                "source:\(context.source)",
//                "application_name:\(context.applicationName)",
//                "signpostName:\(signpostName)"
//            ]
//
//            let measures: MXHistogramMeasures<UnitType>? = histogram
//                .bucketEnumerator
//                .compactMap { $0 as? MXHistogramBucket<UnitType> }
//                .reduce(nil) { measures, bucket in
//                    guard let measures = measures else {
//                        return MXHistogramMeasures(
//                            min: bucket.bucketStart,
//                            max: bucket.bucketEnd,
//                            total: bucket.bucketEnd * Double(bucket.bucketCount),
//                            count: bucket.bucketCount
//                        )
//                    }
//
//                    return MXHistogramMeasures(
//                        min: Swift.min(measures.min, bucket.bucketStart),
//                        max: Swift.max(measures.max, bucket.bucketEnd),
//                        total: measures.total + (bucket.bucketEnd * Double(bucket.bucketCount)),
//                        count: measures.count + bucket.bucketCount
//                    )
//                }
//
//            guard let measures = measures else {
//                return
//            }
//
//            let min = Serie(
//                type: .gauge,
//                interval: nil,
//                metric: "\(metric).min",
//                unit: measures.min.unit.symbol,
//                points: [
//                    Serie.Point(
//                        timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                        value: measures.min.value
//                    )
//                ],
//                resources: [],
//                tags: tags
//            )
//
//            let max = Serie(
//                type: .gauge,
//                interval: nil,
//                metric: "\(metric).max",
//                unit: measures.max.unit.symbol,
//                points: [
//                    Serie.Point(
//                        timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                        value: measures.max.value
//                    )
//                ],
//                resources: [],
//                tags: tags
//            )
//
//            let count = Serie(
//                type: .count,
//                interval: nil,
//                metric: "\(metric).count",
//                unit: nil,
//                points: [
//                    Serie.Point(
//                        timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                        value: Double(measures.count)
//                    )
//                ],
//                resources: [],
//                tags: tags
//            )
//
//            // Just a guess, not a good one
//            let average = measures.total / Double(measures.count)
//            let avg = Serie(
//                type: .gauge,
//                interval: nil,
//                metric: "\(metric).avg",
//                unit: average.unit.symbol,
//                points: [
//                    Serie.Point(
//                        timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
//                        value: average.value
//                    )
//                ],
//                resources: [],
//                tags: tags
//            )
//
//            writer.write(value: MetricMessage.serie(min))
//            writer.write(value: MetricMessage.serie(max))
//            writer.write(value: MetricMessage.serie(count))
//            writer.write(value: MetricMessage.serie(avg))
//        }
    }
}

internal struct MXHistogramMeasures<UnitType> where UnitType: Unit {
    let min: Measurement<UnitType>
    let max: Measurement<UnitType>
    let total: Measurement<UnitType>
    let count: Int
}

#endif
