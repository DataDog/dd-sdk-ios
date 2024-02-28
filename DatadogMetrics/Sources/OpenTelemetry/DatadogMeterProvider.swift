/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

public final class DatadogMeterProvider: OpenTelemetryApi.MeterProvider {
    private weak var core: DatadogCoreProtocol?

    public static func provider(in core: DatadogCoreProtocol = CoreRegistry.default) -> OpenTelemetryApi.MeterProvider {
        DatadogMeterProvider(core: core)
    }

    private init(core: DatadogCoreProtocol) {
        self.core = core
    }

    public func get(instrumentationName: String, instrumentationVersion: String?) -> OpenTelemetryApi.Meter {
        var tags = ["otel-instrumentation-name:\(instrumentationName)"]

        if let version = instrumentationVersion {
            tags.append("otel-instrumentation-version:\(version)")
        }

        return DatadogMeter(
            core: core,
            tags: tags
        )
    }
}

internal struct DatadogMeter: OpenTelemetryApi.Meter {
    weak var core: DatadogCoreProtocol?

    let tags: [String]
    
    func createDoubleMeasure(name: String, absolute: Bool) -> OpenTelemetryApi.AnyMeasureMetric<Double> {
        AnyMeasureMetric(
            DatadogMeasureMetric(
                meter: Meter(
                    name: name,
                    type: .gauge,
                    interval: nil,
                    unit: nil,
                    resources: [],
                    tags: tags,
                    core: core
                )
            )
        )
    }
    
    func createIntMeasure(name: String, absolute: Bool) -> OpenTelemetryApi.AnyMeasureMetric<Int> {
        AnyMeasureMetric(
            DatadogMeasureMetric(
                meter: Meter(
                    name: name,
                    type: .gauge,
                    interval: nil,
                    unit: nil,
                    resources: [],
                    tags: tags,
                    core: core
                )
            )
        )
    }
    
    func createDoubleCounter(name: String, monotonic: Bool) -> OpenTelemetryApi.AnyCounterMetric<Double> {
        AnyCounterMetric(
            DatadogCounterMetric(
                meter: Meter(
                    name: name,
                    type: .count,
                    interval: nil,
                    unit: nil,
                    resources: [],
                    tags: tags,
                    core: core
                )
            )
        )
    }
    
    func createIntCounter(name: String, monotonic: Bool) -> OpenTelemetryApi.AnyCounterMetric<Int> {
        AnyCounterMetric(
            DatadogCounterMetric(
                meter: Meter(
                    name: name,
                    type: .count,
                    interval: nil,
                    unit: nil,
                    resources: [],
                    tags: tags,
                    core: core
                )
            )
        )
    }
    
    func createIntHistogram(name: String, explicitBoundaries: Array<Int>?, absolute: Bool) -> OpenTelemetryApi.AnyHistogramMetric<Int> {
        .init(NoopHistogramMetric())
    }
    
    func createDoubleHistogram(name: String, explicitBoundaries: Array<Double>?, absolute: Bool) -> OpenTelemetryApi.AnyHistogramMetric<Double> {
        .init(NoopHistogramMetric())
    }
    
    func createRawDoubleHistogram(name: String) -> OpenTelemetryApi.AnyRawHistogramMetric<Double> {
        .init(NoopRawHistogramMetric())
    }
    
    func createRawIntHistogram(name: String) -> OpenTelemetryApi.AnyRawHistogramMetric<Int> {
        .init(NoopRawHistogramMetric())
    }
    
    func createRawDoubleCounter(name: String) -> OpenTelemetryApi.AnyRawCounterMetric<Double> {
        .init(NoopRawCounterMetric())
    }
    
    func createRawIntCounter(name: String) -> OpenTelemetryApi.AnyRawCounterMetric<Int> {
        .init(NoopRawCounterMetric())
    }
    
    func createIntObservableGauge(name: String, callback: @escaping (OpenTelemetryApi.IntObserverMetric) -> Void) -> OpenTelemetryApi.IntObserverMetric {
        NoopIntObserverMetric()
    }
    
    func createDoubleObservableGauge(name: String, callback: @escaping (OpenTelemetryApi.DoubleObserverMetric) -> Void) -> OpenTelemetryApi.DoubleObserverMetric {
        NoopDoubleObserverMetric()
    }

    func createDoubleObserver(name: String, absolute: Bool, callback: @escaping (OpenTelemetryApi.DoubleObserverMetric) -> Void) -> OpenTelemetryApi.DoubleObserverMetric {
        NoopDoubleObserverMetric()
    }

    func createIntObserver(name: String, absolute: Bool, callback: @escaping (OpenTelemetryApi.IntObserverMetric) -> Void) -> OpenTelemetryApi.IntObserverMetric {
        NoopIntObserverMetric()
    }

    func getLabelSet(labels: [String: String]) -> OpenTelemetryApi.LabelSet {
        OpenTelemetryApi.LabelSet(labels: labels)
    }
}

//extension DatadogMeter: StableMeter {
//    public func counterBuilder(name: String) -> OpenTelemetryApi.LongCounterBuilder {
//        <#code#>
//    }
//    
//    public func upDownCounterBuilder(name: String) -> OpenTelemetryApi.LongUpDownCounterBuilder {
//        <#code#>
//    }
//    
//    public func histogramBuilder(name: String) -> OpenTelemetryApi.DoubleHistogramBuilder {
//        <#code#>
//    }
//    
//    public func gaugeBuilder(name: String) -> OpenTelemetryApi.DoubleGaugeBuilder {
//        <#code#>
//    }
//}

/// copy: https://github.com/open-telemetry/opentelemetry-swift/blob/main/Sources/OpenTelemetryApi/Metrics/Raw/RawCounterMetric.swift#L63
/// original does not expose `init`.
internal struct NoopRawCounterMetric<T> : OpenTelemetryApi.RawCounterMetric {
    func record(sum: T, startDate: Date, endDate: Date, labels: [String : String]) {}

    func record(sum: T, startDate: Date, endDate: Date, labelset: LabelSet) {}

    func bind(labelset: LabelSet) -> BoundRawCounterMetric<T> {
        BoundRawCounterMetric<T>()
    }

    func bind(labels: [String : String]) -> BoundRawCounterMetric<T> {
        BoundRawCounterMetric<T>()
    }
}

protocol OpenTelemetryMetricValue where Self: AdditiveArithmetic {
    var doubleValue: Double { get }
}

extension Int: OpenTelemetryMetricValue {
    var doubleValue: Double { Double(self) }
}

extension Double: OpenTelemetryMetricValue {
    var doubleValue: Double { self }
}

extension Meter {
    init(_ meter: Meter, labels: [String: String]) {
        self.init(
            name: meter.name,
            type: meter.type,
            interval: meter.interval,
            unit: meter.unit,
            resources: meter.resources,
            tags: meter.tags + labels.map { "\($0):\($1)" },
            core: meter.core
        )
    }
}
