/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class Recorder {
    weak var core: DatadogCoreProtocol?

    @Mutex
    var aggregators: [Submission.Metadata: _Aggregator] = [:]

    private let interval: TimeInterval
    private var workItem: DispatchWorkItem?

    init(
        core: DatadogCoreProtocol,
        interval: TimeInterval = 10
    ) {
        self.core = core
        self.interval = interval

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval, execute: publish)
    }

    func submit(_ submission: Submission) {
        var aggregator = aggregators[submission.metadata] ?? {
            switch submission.metadata.type {
            case .count: return _CountAggregator()
            case .gauge: return _GaugeAggregator()
            case .histogram: return _HistogramAggregator()
            }
        }()

        aggregator.add(submission.point)
        aggregators[submission.metadata] = aggregator
    }

    func publish() {
        defer {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval, execute: publish)
        }

        let aggregators = _aggregators.lock { aggregators in
            defer { aggregators = [:] }
            return aggregators
        }

        core?.scope(for: MetricFeature.name)?.eventWriteContext { context, writer in
            aggregators.forEach { (metadata, aggregator) in
                let metadata = Submission.Metadata(
                    name: "\(context.source).\(context.applicationBundleIdentifier).\(metadata.name)" ,
                    type: metadata.type,
                    interval: Int64(withNoOverflow: self.interval),
                    unit: metadata.unit,
                    resources: metadata.resources,
                    tags: metadata.tags + [
                        "service:\(context.service)",
                        "env:\(context.env)",
                        "version:\(context.version)",
                        "build_number:\(context.buildNumber)",
                        "source:\(context.source)",
                        "application_name:\(context.applicationName)",
                    ]
                )

                let series = aggregator.flush(metadata: metadata)
                series.forEach { writer.write(value: MetricMessage.serie($0)) }
            }
        }
    }
}

internal protocol _Aggregator {
    mutating func add(_ point: Serie.Point)

    func flush(metadata: Submission.Metadata) -> [Serie]
}

internal final class _CountAggregator: _Aggregator {
    var point: Serie.Point?

    func add(_ point: Serie.Point) {
        let current = self.point?.value ?? 0
        self.point = Serie.Point(
            timestamp: point.timestamp,
            value: current + point.value
        )
    }

    func flush(metadata: Submission.Metadata) -> [Serie] {
        guard let point = point else {
            return []
        }

        return [Serie(
            type: .count,
            interval: metadata.interval,
            metric: metadata.name,
            unit: metadata.unit,
            points: [point],
            resources: metadata.resources,
            tags: metadata.tags
        )]
    }
}

internal final class _GaugeAggregator: _Aggregator {
    var point: Serie.Point?

    func add(_ point: Serie.Point) {
        self.point = point
    }

    func flush(metadata: Submission.Metadata) -> [Serie] {
        guard let point = point else {
            return []
        }

        return [Serie(
            type: .count,
            interval: metadata.interval,
            metric: metadata.name,
            unit: metadata.unit,
            points: [point],
            resources: metadata.resources,
            tags: metadata.tags
        )]
    }
}

internal final class _HistogramAggregator: _Aggregator {
    func add(_ point: Serie.Point) {

    }

    func flush(metadata: Submission.Metadata) -> [Serie] {
        []
    }
}
