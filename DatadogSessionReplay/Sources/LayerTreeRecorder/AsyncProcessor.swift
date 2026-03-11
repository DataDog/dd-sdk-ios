/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Lightweight async processing primitive used by the layer-tree pipeline.
//
// `AsyncProcessor` accepts inputs from producer actors (for example, the recorder)
// and forwards them to a processor implementation in submission order. It behaves
// like a serial async queue powered by `AsyncStream`, while allowing callers to
// continue without awaiting downstream processing.

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal protocol Processor<Input> {
    associatedtype Input
    func process(_ input: Input) async
}

@available(iOS 13.0, tvOS 13.0, *)
internal actor AsyncProcessor<Input>: Processor {
    private let continuation: AsyncStream<Input>.Continuation

    init<P>(processor: P, priority: TaskPriority) where P: Processor, P.Input == Input {
        let (stream, continuation) = AsyncStream<Input>.makeStream()
        self.continuation = continuation

        // Detached consumer task that drains the stream sequentially.
        Task(priority: priority) {
            for await input in stream {
                await processor.process(input)
            }
        }
    }

    deinit {
        // Finishing the stream lets the consumer task exit naturally.
        continuation.finish()
    }

    func process(_ input: Input) {
        continuation.yield(input)
    }
}
#endif
