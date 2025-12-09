/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at  (https://www.datadoghq.com/).
 * Copyright 2019-Present , Inc.
 */

import Foundation

// MARK: - MeterProvider

/// Meter provider that exports metrics to .
public final class MeterProvider {
    private let exporter: MetricExporter
    private let pushInterval: TimeInterval
    private let resource: [String: String]

    private var meters: [String: Meter] = [:]
    private let queue = DispatchQueue(label: "com.datadoghq.benchmarks.meter-provider")
    private var timer: DispatchSourceTimer?

    public init(exporter: MetricExporter, pushInterval: TimeInterval, resource: [String: String]) {
        self.exporter = exporter
        self.pushInterval = pushInterval
        self.resource = resource
        startPushTimer()
    }

    deinit {
        timer?.cancel()
    }

    public func get(instrumentationName: String) -> Meter {
        queue.sync {
            if let meter = meters[instrumentationName] {
                return meter
            }
            let meter = Meter(name: instrumentationName, resource: resource)
            meters[instrumentationName] = meter
            return meter
        }
    }

    private func startPushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in
            self?.pushMetrics()
        }
        timer.schedule(deadline: .now() + pushInterval, repeating: pushInterval)
        timer.activate()
        self.timer = timer
    }

    private func pushMetrics() {
        var allSeries: [MetricExporter.Serie] = []

        for (_, meter) in meters {
            allSeries.append(contentsOf: meter.collectAndReset())
        }

        if !allSeries.isEmpty {
            exporter.submit(series: allSeries)
        }
    }
}

// MARK: - Meter

public final class Meter {
    let name: String
    let resource: [String: String]

    private var counters: [String: DoubleCounter] = [:]
    private var measures: [String: DoubleMeasure] = [:]
    private var observableGauges: [String: () -> MetricExporter.Serie?] = [:]
    private let lock = NSLock()

    init(name: String, resource: [String: String]) {
        self.name = name
        self.resource = resource
    }

    public func createDoubleCounter(name: String) -> DoubleCounter {
        lock.lock()
        defer { lock.unlock() }

        if let counter = counters[name] {
            return counter
        }
        let counter = DoubleCounter(name: name, resource: resource)
        counters[name] = counter
        return counter
    }

    public func createDoubleMeasure(name: String) -> DoubleMeasure {
        lock.lock()
        defer { lock.unlock() }

        if let measure = measures[name] {
            return measure
        }
        let measure = DoubleMeasure(name: name, resource: resource)
        measures[name] = measure
        return measure
    }

    public func createDoubleObservableGauge(name: String, callback: @escaping (DoubleObserver) -> Void) -> ObservableGauge {
        lock.lock()
        defer { lock.unlock() }

        let gauge = ObservableGauge(name: name, resource: resource, callback: callback)
        observableGauges[name] = { gauge.collect() }
        return gauge
    }

    func collectAndReset() -> [MetricExporter.Serie] {
        lock.lock()
        defer { lock.unlock() }

        var series: [MetricExporter.Serie] = []

        // Collect counter values
        for (_, counter) in counters {
            if let serie = counter.collectAndReset() {
                series.append(serie)
            }
        }

        // Collect measure values
        for (_, measure) in measures {
            if let serie = measure.collectAndReset() {
                series.append(serie)
            }
        }

        // Collect observable gauge values
        for (_, collector) in observableGauges {
            if let serie = collector() {
                series.append(serie)
            }
        }

        return series
    }
}

// MARK: - Metric Instruments

public final class DoubleCounter {
    let name: String
    let resource: [String: String]
    private var sum: Double = 0
    private var attributes: [String: String] = [:]
    private let lock = NSLock()

    init(name: String, resource: [String: String]) {
        self.name = name
        self.resource = resource
    }

    public func add(value: Double, attributes: [String: String]) {
        lock.lock()
        sum += value
        self.attributes.merge(attributes) { _, new in new }
        lock.unlock()
    }

    func collectAndReset() -> MetricExporter.Serie? {
        lock.lock()
        defer {
            sum = 0
            attributes = [:]
            lock.unlock()
        }

        guard sum != 0 else {
            return nil
        }

        var tags = resource.map { "\($0.key):\($0.value)" }
        tags.append(contentsOf: attributes.map { "\($0.key):\($0.value)" })

        return MetricExporter.Serie(
            type: .count,
            interval: nil,
            metric: name,
            unit: nil,
            points: [MetricExporter.Serie.Point(timestamp: Int64(Date().timeIntervalSince1970), value: sum)],
            resources: [],
            tags: tags
        )
    }
}

public final class DoubleMeasure {
    let name: String
    let resource: [String: String]
    private var lastValue: Double?
    private var attributes: [String: String] = [:]
    private let lock = NSLock()

    init(name: String, resource: [String: String]) {
        self.name = name
        self.resource = resource
    }

    public func record(value: Double, attributes: [String: String]) {
        lock.lock()
        lastValue = value
        self.attributes.merge(attributes) { _, new in new }
        lock.unlock()
    }

    func collectAndReset() -> MetricExporter.Serie? {
        lock.lock()
        defer {
            lastValue = nil
            attributes = [:]
            lock.unlock()
        }

        guard let value = lastValue else {
            return nil
        }

        var tags = resource.map { "\($0.key):\($0.value)" }
        tags.append(contentsOf: attributes.map { "\($0.key):\($0.value)" })

        return MetricExporter.Serie(
            type: .gauge,
            interval: nil,
            metric: name,
            unit: nil,
            points: [MetricExporter.Serie.Point(timestamp: Int64(Date().timeIntervalSince1970), value: value)],
            resources: [],
            tags: tags
        )
    }
}

public final class DoubleObserver {
    private var observedValue: Double?
    private var observedAttributes: [String: String] = [:]
    private let lock = NSLock()

    public func observe(value: Double, attributes: [String: String]) {
        lock.lock()
        observedValue = value
        observedAttributes = attributes
        lock.unlock()
    }

    func reset() {
        lock.lock()
        observedValue = nil
        observedAttributes = [:]
        lock.unlock()
    }

    func getObservation() -> (value: Double, attributes: [String: String])? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = observedValue else {
            return nil
        }
        return (value, observedAttributes)
    }
}

public final class ObservableGauge {
    let name: String
    let resource: [String: String]
    let callback: (DoubleObserver) -> Void
    private let observer = DoubleObserver()

    init(name: String, resource: [String: String], callback: @escaping (DoubleObserver) -> Void) {
        self.name = name
        self.resource = resource
        self.callback = callback
    }

    func collect() -> MetricExporter.Serie? {
        // Reset before callback
        observer.reset()

        // Call the callback to get current value
        callback(observer)

        guard let observation = observer.getObservation() else {
            return nil
        }

        var tags = resource.map { "\($0.key):\($0.value)" }
        tags.append(contentsOf: observation.attributes.map { "\($0.key):\($0.value)" })

        return MetricExporter.Serie(
            type: .gauge,
            interval: nil,
            metric: name,
            unit: nil,
            points: [MetricExporter.Serie.Point(timestamp: Int64(Date().timeIntervalSince1970), value: observation.value)],
            resources: [],
            tags: tags
        )
    }
}
