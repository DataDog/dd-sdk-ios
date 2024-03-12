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

internal class MainAsyncQueue: Queue {
    private let queue: DispatchQueue = .main

    func run(_ block: @escaping () -> Void) {
        queue.async { block() }
    }
}

internal class BackgroundAsyncQueue: Queue {
    private let queue: DispatchQueue

    init(named queueName: String) {
        self.queue = DispatchQueue(label: queueName, qos: .utility, autoreleaseFrequency: .workItem)
    }

    func run(_ block: @escaping () -> Void) {
        queue.async { block() }
    }
}
#endif
