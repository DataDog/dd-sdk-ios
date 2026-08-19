/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
import TestUtilities
@_spi(Internal)
import DatadogInternal
@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
class ViewTreeSnapshotBuilderTests: XCTestCase {
    func testWhenQueryingNodeRecorders_itPassesAppropriateContext() throws {
        // Given
        let view = UIView(frame: .mockRandom())
        let randomRecorderContext: Recorder.Context = .mockRandom()
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(
            viewTreeRecorder: ViewTreeRecorder(nodeRecorders: [nodeRecorder]),
            idsGenerator: NodeIDGenerator(),
            core: PassthroughCoreMock(),
            featureFlags: .allEnabled
        )

        // When
        let snapshot = builder.createSnapshot(of: view, with: randomRecorderContext)

        // Then
        XCTAssertEqual(snapshot.context.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(snapshot.context.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(snapshot.context.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(snapshot.context.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(snapshot.context.date, randomRecorderContext.date)

        let queryContext = try XCTUnwrap(nodeRecorder.queryContexts.first)
        XCTAssertTrue(queryContext.coordinateSpace === view)
        XCTAssertEqual(queryContext.recorder.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(queryContext.recorder.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(queryContext.recorder.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(queryContext.recorder.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(queryContext.recorder.date, randomRecorderContext.date)
    }

    func testItAppliesServerTimeOffsetToSnapshot() {
        // Given
        let now = Date()
        let view = UIView(frame: .mockRandom())
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(
            viewTreeRecorder: ViewTreeRecorder(nodeRecorders: [nodeRecorder]),
            idsGenerator: NodeIDGenerator(),
            core: PassthroughCoreMock(),
            featureFlags: .allEnabled
        )

        // When
        let snapshot = builder.createSnapshot(of: view, with: .mockWith(date: now, rumContext: .mockWith(serverTimeOffset: 1_000)))

        // Then
        XCTAssertGreaterThan(snapshot.date, now)
    }

    func testWhenQueryingNodeRecorders_itCallsAdditionalNodeRecorders() throws {
        // Given
        let view = UIView(frame: .mockRandom())
        let randomRecorderContext: Recorder.Context = .mockRandom()
        let additionalNodeRecorder = SessionReplayNodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [additionalNodeRecorder],
            core: PassthroughCoreMock(),
            featureFlags: .allEnabled
        )

        // When
        let snapshot = builder.createSnapshot(of: view, with: randomRecorderContext)

        // Then
        XCTAssertEqual(snapshot.context.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(snapshot.context.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(snapshot.context.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(snapshot.context.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(snapshot.context.date, randomRecorderContext.date)

        let queryContext = try XCTUnwrap(additionalNodeRecorder.queryContexts.first)
        XCTAssertTrue(queryContext.coordinateSpace === view)
        XCTAssertEqual(queryContext.recorder.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(queryContext.recorder.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(queryContext.recorder.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(queryContext.recorder.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(queryContext.recorder.date, randomRecorderContext.date)
    }

    func testWhenCreatingSnapshot_itWritesHeatmapIdentifiersToRegistry() throws {
        // Given
        let view = UIView.mock(withFixture: .visible(.someAppearance))
        let core = FeatureRegistrationCoreMock()
        let registry = HeatmapIdentifierRegistryMock()
        try core.register(heatmapIdentifierRegistry: registry)
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [],
            core: core,
            featureFlags: .allEnabled
        )
        let context = Recorder.Context.mockWith(
            rumContext: .mockWith(viewPath: "Home")
        )

        // When
        _ = builder.createSnapshot(of: view, with: context)

        // Then
        XCTAssertFalse(registry.identifiers.isEmpty)
    }

    func testWhenCreatingSnapshot_withNoViewPath_itDoesNotWriteToRegistry() throws {
        // Given
        let view = UIView.mock(withFixture: .visible(.someAppearance))
        let core = FeatureRegistrationCoreMock()
        let registry = HeatmapIdentifierRegistryMock()
        try core.register(heatmapIdentifierRegistry: registry)
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [],
            core: core,
            featureFlags: .allEnabled
        )
        let context = Recorder.Context.mockWith(
            rumContext: .mockWith(viewPath: nil)
        )

        // When
        _ = builder.createSnapshot(of: view, with: context)

        // Then
        XCTAssertTrue(registry.identifiers.isEmpty)
    }

    func testWhenCreatingSnapshot_withHeatmapsFlagDisabled_itDoesNotWriteToRegistry() throws {
        // Given
        let view = UIView.mock(withFixture: .visible(.someAppearance))
        let core = FeatureRegistrationCoreMock()
        let registry = HeatmapIdentifierRegistryMock()
        try core.register(heatmapIdentifierRegistry: registry)
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [],
            core: core,
            featureFlags: .defaults
        )
        let context = Recorder.Context.mockWith(
            rumContext: .mockWith(viewPath: "Home")
        )

        // When
        _ = builder.createSnapshot(of: view, with: context)

        // Then
        XCTAssertTrue(registry.identifiers.isEmpty)
    }

    @available(iOS 13.0, *)
    func testSnapshotIncludesEveryEmbeddedContentSlot() {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let firstEmbeddedContentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        firstEmbeddedContentView.dd.setSessionReplaySlotID("first-slot")
        let secondEmbeddedContentView = UIView(frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        secondEmbeddedContentView.dd.setSessionReplaySlotID("second-slot")
        rootView.addSubview(firstEmbeddedContentView)
        rootView.addSubview(secondEmbeddedContentView)
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [],
            core: PassthroughCoreMock(),
            featureFlags: .allEnabled
        )

        // When
        let snapshot = builder.createSnapshot(of: rootView, with: .mockAny())

        // Then
        XCTAssertEqual(Set(snapshot.embeddedContentSlots.values), ["first-slot", "second-slot"])
        XCTAssertEqual(snapshot.embeddedContentSlots.count, 2)
    }

    @available(iOS 13.0, *)
    func testWhenUIKitViewHasSessionReplaySlotID_itIsRecordedAsEmbeddedContent() {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let embeddedContentLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        embeddedContentLabel.text = "Native label"
        embeddedContentLabel.dd.setSessionReplaySlotID("embedded-slot")
        rootView.addSubview(embeddedContentLabel)
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [],
            core: PassthroughCoreMock(),
            featureFlags: .allEnabled
        )

        // When
        let snapshot = builder.createSnapshot(of: rootView, with: .mockAny())

        // Then
        XCTAssertEqual(Set(snapshot.embeddedContentSlots.values), ["embedded-slot"])
        XCTAssertTrue(snapshot.nodes.contains { $0.wireframesBuilder is EmbeddedContentWireframesBuilder })
        XCTAssertFalse(snapshot.nodes.contains { $0.wireframesBuilder is UILabelWireframesBuilder })
    }

    @available(iOS 13.0, *)
    func testDetachedEmbeddedContentViewRemainsCachedWhileAlive() {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let embeddedContentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        embeddedContentView.dd.setSessionReplaySlotID("retained-slot")
        rootView.addSubview(embeddedContentView)
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [],
            core: PassthroughCoreMock(),
            featureFlags: .allEnabled
        )
        let initialSnapshot = builder.createSnapshot(of: rootView, with: .mockAny())
        embeddedContentView.removeFromSuperview()

        // When
        let nextSnapshot = builder.createSnapshot(of: rootView, with: .mockAny())

        // Then
        XCTAssertEqual(nextSnapshot.embeddedContentSlots, initialSnapshot.embeddedContentSlots)
        withExtendedLifetime(embeddedContentView) {}
    }

    @available(iOS 13.0, *)
    func testSnapshotExcludesDeallocatedEmbeddedContentViews() {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let builder = ViewTreeSnapshotBuilder(
            additionalNodeRecorders: [],
            core: PassthroughCoreMock(),
            featureFlags: .allEnabled
        )
        weak var weakEmbeddedContentView: UIView?
        var initialSlots: [WireframeID: String] = [:]
        autoreleasepool {
            let embeddedContentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            embeddedContentView.dd.setSessionReplaySlotID("released-slot")
            weakEmbeddedContentView = embeddedContentView
            rootView.addSubview(embeddedContentView)
            initialSlots = builder.createSnapshot(of: rootView, with: .mockAny()).embeddedContentSlots
            embeddedContentView.removeFromSuperview()
        }

        // When
        let nextSnapshot = builder.createSnapshot(of: rootView, with: .mockAny())

        // Then
        XCTAssertEqual(initialSlots.count, 1)
        XCTAssertNil(weakEmbeddedContentView)
        XCTAssertTrue(nextSnapshot.embeddedContentSlots.isEmpty)
    }
}
#endif
