/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Foundation
import SwiftProtobuf

/// Objective-C facade for the isolated RN benchmark app, not a DatadogFlags public API.
/// The caller must serialize all access, including configuration installation.
@objc(DDFlagsBenchmark)
public final class FlagsBenchmark: NSObject {
    private var bytes: Data?
    private var evaluator: ProtobufRulesEvaluator?

    @objc
    override public init() { super.init() }

    @objc
    public func run(_ request: [String: Any]) -> [String: Any] {
        do {
            switch request["op"] as? String {
            case "preload":
                guard let base64 = request["base64"] as? String,
                      let data = Data(base64Encoded: base64) else { throw PrototypeError.invalidRequest }
                bytes = data
                return ["byteCount": data.count]
            case "installBinary":
                let configuration = try decode()
                evaluator = ProtobufRulesEvaluator(configuration: configuration)
                return ["flagCount": configuration.flags.count]
            case "binaryToJson":
                return ["json": try decode().jsonString()]
            case "installJson":
                guard let json = request["json"] as? String else { throw PrototypeError.invalidRequest }
                let configuration = try ClientRules(jsonString: json)
                evaluator = ProtobufRulesEvaluator(configuration: configuration)
                return ["flagCount": configuration.flags.count]
            case "evaluate":
                guard let evaluator = evaluator else { throw PrototypeError.notInitialized }
                return evaluator.evaluate(try ProtobufRequest(request), timestamp: Date().timeIntervalSince1970 * 1_000)
            case "echo":
                guard let result = request["result"] as? [String: Any] else { throw PrototypeError.invalidRequest }
                return result
            case "controls": return try controls(request)
            case "metadata": return metadata()
            case "saveReport":
                guard let json = request["json"] as? String, let data = json.data(using: .utf8),
                      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw PrototypeError.invalidRequest
                }
                _ = try JSONSerialization.jsonObject(with: data)
                let url = directory.appendingPathComponent("flags-benchmark-result.json")
                try data.write(to: url, options: .atomic)
                return ["path": url.path]
            default: throw PrototypeError.invalidRequest
            }
        } catch {
            // Only deterministic, synthetic benchmark inputs are accepted by this experimental adapter.
            return ["benchmarkError": String(describing: error)]
        }
    }

    private func decode() throws -> ClientRules {
        guard let bytes = bytes else { throw PrototypeError.notInitialized }
        return try ClientRules(serializedBytes: bytes)
    }

    private func controls(_ request: [String: Any]) throws -> [String: Any] {
        guard let raw = request["requests"] as? [[String: Any]], !raw.isEmpty, raw.count <= 10_000 else {
            throw PrototypeError.invalidRequest
        }
        let requests = try raw.map(ProtobufRequest.init)
        let count = try positiveCount(request["iterations"])
        let warmup = try positiveCount(request["warmup"])
        let decodeCount = try positiveCount(request["decodeIterations"])
        let engine = ProtobufRulesEvaluator(configuration: try decode())
        var decodeTimes: [Double] = []
        var evaluationTimes: [Double] = []
        var clockTimes: [Double] = []
        var flagCount = 0
        var checksum = 0
        var warmupChecksum = 0
        for _ in 0..<decodeCount {
            let start = DispatchTime.now().uptimeNanoseconds
            let decoded = try decode()
            decodeTimes.append(Self.elapsedMilliseconds(start))
            flagCount = decoded.flags.count
        }
        for index in 0..<warmup {
            let result = engine.evaluate(requests[index % requests.count], timestamp: Date().timeIntervalSince1970 * 1_000)
            warmupChecksum += result["value"] as? Bool == true ? 1 : 0
        }
        for index in 0..<count {
            let input = requests[index % requests.count]
            let start = DispatchTime.now().uptimeNanoseconds
            let result = engine.evaluate(input, timestamp: Date().timeIntervalSince1970 * 1_000)
            evaluationTimes.append(Self.elapsedMilliseconds(start))
            guard result["reason"] as? String != "ERROR" else { throw PrototypeError.unsupportedWorkload }
            checksum += result["value"] as? Bool == true ? 1 : 0
            let clockStart = DispatchTime.now().uptimeNanoseconds
            clockTimes.append(Self.elapsedMilliseconds(clockStart))
        }
        return [
            "decode": Self.summarize(decodeTimes), "directEvaluation": Self.summarize(evaluationTimes),
            "clock": Self.summarize(clockTimes), "flagCount": flagCount, "checksum": checksum,
            "warmupChecksum": warmupChecksum,
            "inputConversion": "preconverted; excluded from native-direct control",
        ]
    }

    private func positiveCount(_ value: Any?) throws -> Int {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.rounded() == value.doubleValue,
              value.doubleValue >= 1, value.doubleValue <= 100_000 else { throw PrototypeError.invalidRequest }
        return value.intValue
    }

    private static func elapsedMilliseconds(_ start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    internal static func summarize(_ values: [Double]) -> [String: Any] {
        let sorted = values.sorted()
        func percentile(_ fraction: Double) -> Double { sorted[Int(ceil(fraction * Double(sorted.count))) - 1] * 1_000 }
        return [
            "count": sorted.count, "p50Us": percentile(0.5), "p95Us": percentile(0.95), "p99Us": percentile(0.99),
            "meanUs": values.reduce(0, +) / Double(values.count) * 1_000, "maxUs": (sorted.last ?? 0) * 1_000,
        ]
    }

    private func metadata() -> [String: Any] {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "machine": machine, "simulator": simulator, "nativeDebug": debug,
            "swiftProtobuf": "1.38.1", "nativeWorkload": "client-protobuf boolean benchmark subset",
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
        ]
    }
}
