/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class SlowProfileSpan {
    let name: String
    let id: Int
    let parentID: Int?
    weak var profiler: SlowSingleThreadProfiler?

    let startTime: DispatchTime = .now()
    var finishTime: DispatchTime? = nil

    init(name: String, id: Int, parentID: Int?, profiler: SlowSingleThreadProfiler) {
        self.name = name
        self.id = id
        self.parentID = parentID
        self.profiler = profiler
    }

    func finish() {
        finishTime = .now()
        profiler?.finish(span: self)
    }
}

public class SlowSingleThreadProfiler {
    var currentID: Int = 0
    var finishedSpans: [SlowProfileSpan] = []
    var activeSpans: [SlowProfileSpan] = []

    func startRootSpan(named spanName: String) -> SlowProfileSpan {
        assert(activeSpans.isEmpty)

        let span = SlowProfileSpan(name: spanName, id: nextID(), parentID: nil, profiler: self)
        activeSpans.append(span)
        return span
    }

    func startChildSpan(named spanName: String, childOf parentSpan: SlowProfileSpan? = nil) -> SlowProfileSpan {
        assert(!activeSpans.isEmpty)

        let parentID = parentSpan?.id ?? activeSpans.last!.id
        let span = SlowProfileSpan(name: spanName, id: nextID(), parentID: parentID, profiler: self)
        activeSpans.append(span)
        return span
    }

    func finish(span: SlowProfileSpan) {
        activeSpans.removeAll(where: { $0.id == span.id })
        finishedSpans.append(span)
    }

    private func nextID() -> Int {
        defer { currentID += 1 }
        return currentID
    }
}

internal func dumpFinishedSpans(finishedSpans: [SlowProfileSpan], baseTime: DispatchTime) -> String {
    func dump(span: SlowProfileSpan, indent: String, into outputs: inout [String]) {
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
