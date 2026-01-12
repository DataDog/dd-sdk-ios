/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

internal protocol Queue: AnyObject {
    func run(_ block: @escaping () -> Void)
}

internal class AsyncQueue: Queue {
    fileprivate let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func run(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}

internal final class MainAsyncQueue: AsyncQueue {
    init() {
        super.init(queue: .main)
    }
}

internal final class BackgroundAsyncQueue: AsyncQueue {
    init(label: String, qos: DispatchQoS = .utility, attributes: DispatchQueue.Attributes = [], autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency = .workItem, target: AsyncQueue? = nil) {
        super.init(
            queue: DispatchQueue(label: label, qos: qos, attributes: attributes, autoreleaseFrequency: autoreleaseFrequency, target: target?.queue)
        )
    }
}

internal final class MainQueue: Queue {
    func run(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
#endif
