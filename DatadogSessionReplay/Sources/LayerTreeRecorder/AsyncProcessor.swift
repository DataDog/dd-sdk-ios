/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal protocol Processor {
    associatedtype Input
    func process(_ input: Input) async
}

@available(iOS 13.0, tvOS 13.0, *)
internal actor AsyncProcessor<Input> {
    private let continuation: AsyncStream<Input>.Continuation

    init<P>(processor: P, priority: TaskPriority) where P: Processor, P.Input == Input {
        let (stream, continuation) = AsyncStream<Input>.makeStream()
        self.continuation = continuation

        Task(priority: priority) {
            for await input in stream {
                await processor.process(input)
            }
        }
    }

    deinit {
        continuation.finish()
    }

    func process(_ input: Input) {
        continuation.yield(input)
    }
}
#endif
