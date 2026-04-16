/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogTimeseries

// MARK: - Argument parsing

struct RunnerArgs {
    var fixturePath: String = ""
    var outputDir: String = ""
    var threshold: Double = 1_000_000
    var heartbeat: Int64 = 30
    var windowSeconds: Int64 = 5
    var aggregate: AggregateFunction = .max
}

func parseArgs() -> RunnerArgs {
    var args = RunnerArgs()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        switch argv[i] {
        case "--fixture-path":
            i += 1; args.fixturePath = argv[i]
        case "--output-dir":
            i += 1; args.outputDir = argv[i]
        case "--threshold":
            i += 1; args.threshold = Double(argv[i]) ?? args.threshold
        case "--heartbeat":
            i += 1; args.heartbeat = Int64(argv[i]) ?? args.heartbeat
        case "--window":
            i += 1; args.windowSeconds = Int64(argv[i]) ?? args.windowSeconds
        case "--aggregate":
            i += 1
            switch argv[i] {
            case "avg":  args.aggregate = .avg
            case "min":  args.aggregate = .min
            case "last": args.aggregate = .last
            default:     args.aggregate = .max
            }
        default:
            break
        }
        i += 1
    }
    return args
}

// MARK: - Pipeline helpers

struct PipelineResult {
    let events: [Data]
    var eventCount: Int { events.count }
    var dataPointCount: Int {
        let decoder = JSONDecoder()
        return events.compactMap { data -> Int? in
            let event = try? decoder.decode(TimeseriesEvent.self, from: data)
            return event?.timeseries.data.count
        }.reduce(0, +)
    }
}

func runPipeline(csvContent: String, metric: TimeseriesName, filter: SampleFilter) throws -> PipelineResult {
    let config = TimeseriesConfig(
        applicationId: "runner-app-id",
        sessionId: "runner-session-id",
        sessionType: "user",
        source: "ios",
        service: nil,
        version: nil
    )
    let provider = CSVDataProvider(csvContent: csvContent, metric: metric)
    let pipeline = TimeseriesPipeline(provider: provider, config: config, metricName: metric, filter: filter)
    let events = try pipeline.processAll()
    return PipelineResult(events: events)
}

// MARK: - Output

struct MetricStats: Codable {
    let eventCount: Int
    let dataPointCount: Int
}

struct FilterStats: Codable {
    let memory: MetricStats
    let cpu: MetricStats
}

struct RunnerOutput: Codable {
    let passthrough: FilterStats
    let deadband: FilterStats
    let window: FilterStats
}

// MARK: - Main

let args = parseArgs()

guard !args.fixturePath.isEmpty, !args.outputDir.isEmpty else {
    fputs("Error: --fixture-path and --output-dir are required\n", stderr)
    exit(1)
}

let csvContent: String
do {
    csvContent = try String(contentsOfFile: args.fixturePath, encoding: .utf8)
} catch {
    fputs("Error reading fixture: \(error)\n", stderr)
    exit(1)
}

// heartbeat interval in nanoseconds (fixture timestamps are in nanoseconds)
let heartbeatNs = args.heartbeat * 1_000_000_000
let windowNs = args.windowSeconds * 1_000_000_000

let filters: [(name: String, filter: SampleFilter)] = [
    ("passthrough", PassThroughFilter()),
    ("deadband", DeadbandFilter(threshold: args.threshold, heartbeatInterval: heartbeatNs)),
    ("window", WindowAggregateFilter(windowDuration: windowNs, function: args.aggregate)),
]

var allResults: [(name: String, memory: PipelineResult, cpu: PipelineResult)] = []

for entry in filters {
    // Re-instantiate per-metric because filters are stateful
    let memFilter: SampleFilter
    let cpuFilter: SampleFilter
    switch entry.name {
    case "deadband":
        memFilter = DeadbandFilter(threshold: args.threshold, heartbeatInterval: heartbeatNs)
        cpuFilter = DeadbandFilter(threshold: args.threshold, heartbeatInterval: heartbeatNs)
    case "window":
        memFilter = WindowAggregateFilter(windowDuration: windowNs, function: args.aggregate)
        cpuFilter = WindowAggregateFilter(windowDuration: windowNs, function: args.aggregate)
    default:
        memFilter = PassThroughFilter()
        cpuFilter = PassThroughFilter()
    }

    do {
        let memResult = try runPipeline(csvContent: csvContent, metric: .memoryUsage, filter: memFilter)
        let cpuResult = try runPipeline(csvContent: csvContent, metric: .cpuUsage, filter: cpuFilter)
        allResults.append((name: entry.name, memory: memResult, cpu: cpuResult))
    } catch {
        fputs("Error running \(entry.name) pipeline: \(error)\n", stderr)
        exit(1)
    }
}

// Write ndjson output files
let fm = FileManager.default
try? fm.createDirectory(atPath: args.outputDir, withIntermediateDirectories: true)

for entry in allResults {
    for (metricName, result) in [("memory", entry.memory), ("cpu", entry.cpu)] {
        let filename = "\(entry.name)_\(metricName).ndjson"
        let path = (args.outputDir as NSString).appendingPathComponent(filename)
        let lines = result.events.compactMap { String(data: $0, encoding: .utf8) }
        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// Build JSON summary output
func statsFor(name: String) -> FilterStats {
    let entry = allResults.first { $0.name == name }!
    return FilterStats(
        memory: MetricStats(eventCount: entry.memory.eventCount, dataPointCount: entry.memory.dataPointCount),
        cpu: MetricStats(eventCount: entry.cpu.eventCount, dataPointCount: entry.cpu.dataPointCount)
    )
}

let output = RunnerOutput(
    passthrough: statsFor(name: "passthrough"),
    deadband: statsFor(name: "deadband"),
    window: statsFor(name: "window")
)

// Also emit first events for each filter as "first_event_<filter>" keys
// We emit everything as a single JSON object to stdout
struct FullOutput: Codable {
    let stats: RunnerOutput
    let firstEvents: [String: String]
}

var firstEvents: [String: String] = [:]
for entry in allResults {
    if let firstData = entry.memory.events.first, let str = String(data: firstData, encoding: .utf8) {
        firstEvents["\(entry.name)_memory"] = str
    }
    if let firstData = entry.cpu.events.first, let str = String(data: firstData, encoding: .utf8) {
        firstEvents["\(entry.name)_cpu"] = str
    }
}

let fullOutput = FullOutput(stats: output, firstEvents: firstEvents)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let jsonData = try? encoder.encode(fullOutput), let jsonStr = String(data: jsonData, encoding: .utf8) {
    print(jsonStr)
} else {
    fputs("Error encoding output JSON\n", stderr)
    exit(1)
}
