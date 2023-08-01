/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// swiftlint:disable force_unwrapping
public struct FastProfileSpan {
    let name: String
    let id: Int
    let parentID: Int?

    weak var profiler: FastTimeProfiler?

    let startTime: DispatchTime
    var finishTime: DispatchTime?

    func finish() {
        profiler?.finish(spanID: id)
    }
}

public class FastTimeProfiler {
    var currentID: Int = 0
    var spansByID: [Int: FastProfileSpan] = [:]
    var activeSpanID: Int? = nil

    func startSpan(named spanName: String) -> FastProfileSpan {
        let span = FastProfileSpan(name: spanName, id: nextID(), parentID: activeSpanID, profiler: self, startTime: .now(), finishTime: nil)
        spansByID[span.id] = span
        activeSpanID = span.id
        return span
    }

    func finish(spanID: Int) {
        spansByID[spanID]?.finishTime = .now()
        activeSpanID = spansByID[spanID]?.parentID
    }

    private func nextID() -> Int {
        defer { currentID += 1 }
        return currentID
    }
}

internal func dumpFinishedSpans(spansByID: [Int: FastProfileSpan], baseTime: DispatchTime) -> String {
    let finishedSpans = spansByID.values.map({ ($0, $0.name) }).sorted(by: { one, two in one.1 < two.1 }).map { $0.0 }

    func dump(span: FastProfileSpan, indent: String, into outputs: inout [String]) {
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

// swiftlint:enable force_unwrapping
