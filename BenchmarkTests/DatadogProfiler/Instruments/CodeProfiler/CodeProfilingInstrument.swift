/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct CodeProfilingInstrumentConfiguration: InstrumentConfiguration {
    public let profileName: String
    public let estimatedSampleInterval: TimeInterval
    public let metricName: String
    public let metricTags: [String]

    public init(
        profileName: String,
        estimatedSampleInterval: TimeInterval,
        metricName: String,
        metricTags: [String]
    ) {
        precondition(estimatedSampleInterval > 0)
        self.profileName = profileName
        self.estimatedSampleInterval = estimatedSampleInterval
        self.metricName = metricName
        self.metricTags = metricTags
    }

    public func createInstrument(with profilerConfiguration: ProfilerConfiguration) -> Any {
        return CodeProfilingInstrument(
            instrumentName: "Code Profiler \(profileName)",
            estimatedSampleInterval: estimatedSampleInterval,
            metricUploader: MetricUploader(
                apiKey: profilerConfiguration.apiKey,
                metricConfiguration: MetricConfiguration(name: metricName, tags: metricTags, type: .gauge)
            )
        )
    }

    public var description: String {
        """
        Code Profiling Instrument:
        - profileName: \(profileName)
        - estimatedSampleInterval: \(estimatedSampleInterval)s
        - metricName:
            - \(metricName)
        - metricTags:
        \(metricTags.map({ "    - \($0)" }).joined(separator: "\n"))
        """
    }
}

internal class CodeProfilingInstrument: Instrument {
    private let estimatedSampleInterval: TimeInterval
    private let uploader: MetricUploader
    private var profiler: CodeProfiler? = nil

    init(
        instrumentName: String,
        estimatedSampleInterval: TimeInterval,
        metricUploader: MetricUploader
    ) {
        self.instrumentName = instrumentName
        self.estimatedSampleInterval = estimatedSampleInterval
        self.uploader = metricUploader
    }

    let instrumentName: String

    func setUp(measurementDuration: TimeInterval) {
        profiler = CodeProfiler(spansCount: Int(measurementDuration / estimatedSampleInterval))
    }

    func start() {}
    func stop() {}

    func uploadResults(completion: @escaping (InstrumentUploadResult) -> Void) {
//        let finishedSpans = samples[0..<currentSampleIndex]
//
//        for (idx, sample) in measuredSamples.enumerated() {
//            debug("Measure #\(idx): \(sample.footprint.bytesAsPrettyKB) -- \(Date(timeIntervalSince1970: sample.timestamp))")
//        }
//
//        let dataPoints = measuredSamples.map { MetricDataPoint(timestamp: UInt64($0.timestamp), value: $0.footprint) }
//        uploader.send(metricPoints: dataPoints, completion: completion)
    }

    func tearDown() {
        profiler = nil
    }
}

internal struct Span {
    var name: String = ""
    let id: Int
    var parentID: Int?

    weak var profiler: CodeProfiler?

    var startTime: DispatchTime?
    var finishTime: DispatchTime?
}

internal class CodeProfiler {
    private var currentID: Int = 0
    private var spans: [Span] // indexed by ID
    private var activeSpanID: Int? = nil

    init(spansCount: Int) {
        spans = []
        spans = (0..<spansCount).map { Span(id: $0, profiler: self) }
    }

    func startActiveSpan(named spanName: String) {
        let id = nextID()
        defer { activeSpanID = id }
        spans[id].name = spanName
        spans[id].parentID = activeSpanID
        spans[id].startTime = .now()
    }

    func finishActiveSpan() {
        guard let spanID = activeSpanID else {
            return
        }
        spans[spanID].finishTime = .now()
        activeSpanID = spans[spanID].parentID
    }

    var finishedSpans: [Span] {
        return Array(spans[0..<currentID])
    }

    private func nextID() -> Int {
        defer { currentID += 1 }
        return currentID
    }
}

internal func dumpFinishedSpans(finishedSpans: [Span], baseTime: DispatchTime) -> String {
    let finishedSpans = finishedSpans.prefix(while: { $0.startTime != nil })

    func dump(span: Span, indent: String, into outputs: inout [String]) {
        let d = indent + "[#\(span.name)]"
        outputs.append(d)
        let children = finishedSpans.filter { $0.parentID == span.id }
        children.forEach { dump(span: $0, indent: indent + "   ", into: &outputs) }
    }

    let rootSpans = finishedSpans.filter { $0.parentID == nil }

    var dumps: [String] = []
    rootSpans.forEach { dump(span: $0, indent: "", into: &dumps) }
    return dumps.joined(separator: "\n")
}
