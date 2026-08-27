/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct EmbeddedContentViewRecorderTests {
    @available(iOS 13.0, *)
    @Test("Leaves views without a slot ID to other recorders")
    func viewsWithoutSlotIDAreNotRecorded() {
        // Given
        let recorder = EmbeddedContentViewRecorder(identifier: UUID())
        let context = ViewTreeRecordingContext.mockWith()
        let view = UIView()

        // When
        let semantics = recorder.semantics(
            of: view,
            with: .mock(fixture: .visible()),
            in: context
        )

        // Then
        #expect(semantics == nil)
        #expect(context.embeddedContentViewCache.count == 0)
    }

    @available(iOS 13.0, *)
    @Test("Uses the opaque slot ID independently from the generated wireframe ID")
    func embeddedContentViewsUseIndependentSlotAndWireframeIDs() throws {
        // Given
        let recorder = EmbeddedContentViewRecorder(identifier: UUID())
        let context = ViewTreeRecordingContext.mockWith()
        let embeddedContentView = UIView()
        embeddedContentView.dd.setSessionReplaySlotID("opaque-slot")

        // When
        let semantics = try #require(
            recorder.semantics(
                of: embeddedContentView,
                with: .mock(fixture: .visible()),
                in: context
            ) as? SpecificElement
        )
        let wireframesBuilder = try #require(
            semantics.nodes.first?.wireframesBuilder as? EmbeddedContentWireframesBuilder
        )
        let wireframe = try #require(
            wireframesBuilder.buildWireframes(with: WireframesBuilder()).first
        )

        // Then
        #expect(wireframesBuilder.slotID == "opaque-slot")
        #expect(String(wireframesBuilder.wireframeID) != wireframesBuilder.slotID)
        #expect(
            context.embeddedContentViewCache.object(forKey: embeddedContentView)?.int64Value
                == wireframesBuilder.wireframeID
        )
        guard case let .embeddedContentWireframe(embeddedContentWireframe) = wireframe else {
            Issue.record("Embedded content views must produce embedded-content wireframes")
            return
        }
        #expect(embeddedContentWireframe.id == wireframesBuilder.wireframeID)
        #expect(embeddedContentWireframe.slotId == "opaque-slot")
        #expect(embeddedContentWireframe.isVisible == true)
        guard case .ignore = semantics.subtreeStrategy else {
            Issue.record("Embedded content views must stop native subtree traversal")
            return
        }
    }

    @available(iOS 13.0, *)
    @Test("Stops traversal below embedded content views")
    func embeddedContentViewSubtreesAreIgnored() {
        // Given
        let recorder = EmbeddedContentViewRecorder(identifier: UUID())
        let fallbackRecorder = NodeRecorderMock(resultForView: { _ in
            SpecificElement(
                subtreeStrategy: .record,
                nodes: [Node(viewAttributes: .mockAny(), wireframesBuilder: NOPWireframesBuilderMock())]
            )
        })
        let embeddedContentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        embeddedContentView.dd.setSessionReplaySlotID("opaque-slot")
        embeddedContentView.addSubview(UIView(frame: embeddedContentView.bounds))
        let context = ViewTreeRecordingContext.mockWith(coordinateSpace: embeddedContentView)
        let viewTreeRecorder = ViewTreeRecorder(nodeRecorders: [recorder, fallbackRecorder])

        // When
        let nodes = viewTreeRecorder.record(embeddedContentView, in: context)

        // Then
        #expect(nodes.count == 1)
        #expect(fallbackRecorder.queriedViews.isEmpty)
    }

    @available(iOS 13.0, *)
    @Test("Uses the native hidden placeholder without discarding a previously recorded embedded slot")
    func hiddenEmbeddedContentViewsUseNativePlaceholderAndKeepCachedSlot() throws {
        // Given
        let embeddedContentRecorder = EmbeddedContentViewRecorder(identifier: UUID())
        let embeddedContentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        embeddedContentView.dd.setSessionReplaySlotID("opaque-slot")
        let context = ViewTreeRecordingContext.mockWith(coordinateSpace: embeddedContentView)
        _ = embeddedContentRecorder.semantics(
            of: embeddedContentView,
            with: .mock(fixture: .visible()),
            in: context
        )
        let cachedWireframeID = try #require(
            context.embeddedContentViewCache.object(forKey: embeddedContentView)
        )
        let viewTreeRecorder = ViewTreeRecorder(
            nodeRecorders: [
                embeddedContentRecorder,
                UIViewRecorder(identifier: UUID())
            ]
        )

        // When
        embeddedContentView.dd.sessionReplayPrivacyOverrides.hide = true
        let nodes = viewTreeRecorder.record(embeddedContentView, in: context)
        let wireframe = try #require(
            nodes.first?.wireframesBuilder.buildWireframes(with: WireframesBuilder()).first
        )

        // Then
        guard case let .placeholderWireframe(placeholder) = wireframe else {
            Issue.record("Hidden embedded content views must produce native placeholder wireframes")
            return
        }
        #expect(placeholder.label == "Hidden")
        #expect(
            context.embeddedContentViewCache.object(forKey: embeddedContentView) == cachedWireframeID
        )
    }

    @available(iOS 13.0, *)
    @Test("Produces no visible wireframe for invisible embedded content views")
    func invisibleEmbeddedContentViewsProduceNoVisibleWireframe() throws {
        // Given
        let recorder = EmbeddedContentViewRecorder(identifier: UUID())
        let context = ViewTreeRecordingContext.mockWith()
        let embeddedContentView = UIView()
        embeddedContentView.dd.setSessionReplaySlotID("opaque-slot")

        // When
        let semantics = try #require(
            recorder.semantics(
                of: embeddedContentView,
                with: .mock(fixture: .invisible),
                in: context
            ) as? SpecificElement
        )
        let wireframesBuilder = try #require(
            semantics.nodes.first?.wireframesBuilder as? EmbeddedContentWireframesBuilder
        )
        let wireframes = wireframesBuilder.buildWireframes(with: WireframesBuilder())

        // Then
        #expect(wireframes.isEmpty)
        #expect(
            context
                .embeddedContentViewCache
                .object(forKey: embeddedContentView)?
                .int64Value == wireframesBuilder.wireframeID
        )
    }

    @available(iOS 13.0, *)
    @Test("Keeps slots independent for multiple embedded content views")
    func embeddedContentViewsKeepIndependentSlots() throws {
        // Given
        let recorder = EmbeddedContentViewRecorder(identifier: UUID())
        let context = ViewTreeRecordingContext.mockWith()
        let firstEmbeddedContentView = UIView()
        firstEmbeddedContentView.dd.setSessionReplaySlotID("first-slot")
        let secondEmbeddedContentView = UIView()
        secondEmbeddedContentView.dd.setSessionReplaySlotID("second-slot")

        // When
        let firstSemantics = try #require(
            recorder.semantics(
                of: firstEmbeddedContentView,
                with: .mock(fixture: .visible()),
                in: context
            ) as? SpecificElement
        )
        let secondSemantics = try #require(
            recorder.semantics(
                of: secondEmbeddedContentView,
                with: .mock(fixture: .visible()),
                in: context
            ) as? SpecificElement
        )
        let firstBuilder = try #require(
            firstSemantics.nodes.first?.wireframesBuilder as? EmbeddedContentWireframesBuilder
        )
        let secondBuilder = try #require(
            secondSemantics.nodes.first?.wireframesBuilder as? EmbeddedContentWireframesBuilder
        )

        // Then
        #expect(firstBuilder.wireframeID != secondBuilder.wireframeID)
        #expect(
            context
                .embeddedContentViewCache
                .object(forKey: firstEmbeddedContentView)?
                .int64Value == firstBuilder.wireframeID
        )
        #expect(
            context
                .embeddedContentViewCache
                .object(forKey: secondEmbeddedContentView)?
                .int64Value == secondBuilder.wireframeID
        )
    }
}
#endif
