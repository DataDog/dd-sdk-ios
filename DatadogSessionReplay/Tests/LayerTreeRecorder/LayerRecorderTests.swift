/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct LayerRecorderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    enum Fixtures {
        struct NOPTelemetry: Telemetry {
            func send(telemetry: TelemetryMessage) {}
        }

        static func context(
            touchPrivacy: TouchPrivacyLevel = .show,
            viewServerTimeOffset: TimeInterval? = 2
        ) -> LayerRecordingContext {
            LayerRecordingContext(
                textAndInputPrivacy: .maskAll,
                imagePrivacy: .maskAll,
                touchPrivacy: touchPrivacy,
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: viewServerTimeOffset,
                viewPath: "/view",
                date: Date(timeIntervalSince1970: 10),
                telemetry: NOPTelemetry()
            )
        }

        @MainActor
        static func layerTreeSnapshot(context: LayerRecordingContext) throws -> LayerTreeSnapshot {
            let rootLayer = CALayer()
            rootLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 200)

            return LayerTreeSnapshot(
                date: context.date,
                context: context,
                viewportSize: rootLayer.bounds.size,
                root: try #require(CALayerSnapshot(from: rootLayer, in: .mockAny())),
                webViewSlotIDs: []
            )
        }

        static func touchSnapshot() -> TouchSnapshot {
            TouchSnapshot(
                date: Date(timeIntervalSince1970: 12),
                touches: [
                    .init(
                        id: 42,
                        phase: .down,
                        date: Date(timeIntervalSince1970: 12),
                        position: CGPoint(x: 10, y: 20),
                        touchOverride: nil
                    )
                ]
            )
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures layer tree and touch snapshots")
    func capturesLayerTreeAndTouchSnapshots() async throws {
        // Given
        let context = Fixtures.context(touchPrivacy: .hide, viewServerTimeOffset: 1_234)
        let snapshotBuilder = LayerTreeSnapshotBuilderSpy(nextSnapshot: try Fixtures.layerTreeSnapshot(context: context))
        let touchSnapshotProducer = TouchSnapshotProducerSpy(nextSnapshot: Fixtures.touchSnapshot())
        let recorder = try LayerRecorder(
            snapshotBuilder: snapshotBuilder,
            uiApplicationSwizzler: UIApplicationSwizzler(handler: UIEventHandlerMock()),
            touchSnapshotProducer: touchSnapshotProducer
        )

        // When
        await recorder.scheduleRecording(.init(), context: context)
        try await withTimeout {
            await touchSnapshotProducer.waitUntilCalled()
        }

        // Then
        #expect(snapshotBuilder.contexts.count == 1)
        #expect(snapshotBuilder.contexts.first?.applicationID == "app-id")
        #expect(touchSnapshotProducer.contexts.count == 1)
        #expect(touchSnapshotProducer.contexts.first?.touchPrivacy == .hide)
        #expect(touchSnapshotProducer.contexts.first?.viewServerTimeOffset == 1_234)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
@MainActor
private final class LayerTreeSnapshotBuilderSpy: LayerTreeSnapshotBuilding {
    private(set) var contexts: [LayerRecordingContext] = []
    var nextSnapshot: LayerTreeSnapshot?

    init(nextSnapshot: LayerTreeSnapshot?) {
        self.nextSnapshot = nextSnapshot
    }

    func createSnapshot(context: LayerRecordingContext) -> LayerTreeSnapshot? {
        contexts.append(context)
        return nextSnapshot
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class TouchSnapshotProducerSpy: TouchSnapshotProducer, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private let nextSnapshot: TouchSnapshot?
    private var recordedContexts: [TouchSnapshotContext] = []

    var contexts: [TouchSnapshotContext] {
        lock.lock()
        defer { lock.unlock() }

        return recordedContexts
    }

    init(nextSnapshot: TouchSnapshot?) {
        self.nextSnapshot = nextSnapshot
    }

    func takeSnapshot(context: TouchSnapshotContext) -> TouchSnapshot? {
        lock.lock()
        recordedContexts.append(context)
        let continuations = self.continuations
        self.continuations = []
        lock.unlock()

        continuations.forEach { $0.resume() }

        return nextSnapshot
    }

    func waitUntilCalled() async {
        if !contexts.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            let shouldResume = !recordedContexts.isEmpty

            if !shouldResume {
                continuations.append(continuation)
            }

            lock.unlock()

            if shouldResume {
                continuation.resume()
            }
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class UIEventHandlerMock: UIEventHandler {
    func notify_sendEvent(application _: UIApplication, event _: UIEvent) {}
}

@available(iOS 13.0, tvOS 13.0, *)
private enum TimeoutError: Error {
    case timeout
}

@available(iOS 13.0, tvOS 13.0, *)
private func withTimeout(
    seconds: TimeInterval = 1,
    operation: @escaping @Sendable () async -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timeout
        }

        try await group.next()
        group.cancelAll()
    }
}
#endif
