/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// swiftlint:disable force_unwrapping
public struct FastestProfileSpan {
    var name: String = ""
    let id: Int
    var parentID: Int?

    weak var profiler: FastestTimeProfiler?

    var startTime: DispatchTime?
    var finishTime: DispatchTime?
}

public class FastestTimeProfiler {
    var currentID: Int = 0
    var spans: [FastestProfileSpan] // indexed by ID
    var activeSpanID: Int? = nil

    init(spansCount: Int) {
        spans = []
        spans = (0..<spansCount).map { FastestProfileSpan(id: $0, profiler: self) }
    }

    func startSpan(named spanName: String) {
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

    private func nextID() -> Int {
        defer { currentID += 1 }
        return currentID
    }
}

internal func dumpFinishedSpans(finishedSpans: [FastestProfileSpan], baseTime: DispatchTime) -> String {
    let finishedSpans = finishedSpans.prefix(while: { $0.startTime != nil })

    func dump(span: FastestProfileSpan, indent: String, into outputs: inout [String]) {
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
