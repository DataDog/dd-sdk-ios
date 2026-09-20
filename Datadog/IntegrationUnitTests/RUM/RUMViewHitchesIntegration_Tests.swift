/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// TODO: RUM-16908 Merge into `RUMViewHitchesIntegration` once `viewUpdates` feature flag is removed

import XCTest
import TestUtilities
@testable import DatadogRUM
@testable import DatadogInternal

/// Mirrors `RUMViewHitchesIntegrationTests` with `featureFlags[.viewUpdates] = true`.
/// With the flag the stop-view write produces a `RUMViewUpdateEvent` (delta). Assertions fold
/// the target view's full baseline and ordered deltas, because omitted delta fields are unchanged.
final class RUMViewHitchesIntegration_Tests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testViewHitchesNotCollected_whenFeatureFlagIsDisabled() throws {
        // Given
        let viewName = "MyView"
        var rumConfig = RUM.Configuration(applicationID: .mockAny(), trackSlowFrames: false)
        rumConfig.featureFlags = [.viewUpdates: true]
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)
        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customViews = session.views.filter { $0.name == viewName }
        XCTAssertEqual(customViews.count, 1)
        let customView = try XCTUnwrap(customViews.first)
        let documents = hitchDocuments(for: customView)

        let reconstructed = try XCTUnwrap(reconstructHitches(from: documents))
        XCTAssertFalse(reconstructed.isActive)
        XCTAssertEqual(reconstructed.slowFramesCount, 0)
    }

    func testViewHitchesCollected_whenFeatureFlagIsEnabled() throws {
        #if os(watchOS)
        throw XCTSkip("Slow frame tracking is not supported on watchOS (no CADisplayLink)")
        #endif
        // Given
        let viewName = "MyView"
        var rumConfig = RUM.Configuration(applicationID: .mockAny())
        rumConfig.featureFlags = [.viewUpdates: true]
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)

        let completion = expectation(description: "Wait for some slow frames")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // sleep main thread to have some slow frames
            Thread.sleep(forTimeInterval: 0.1)

            // schedule completion to the next runloop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { completion.fulfill() }
        }

        wait(for: [completion], timeout: 2)

        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customViews = session.views.filter { $0.name == viewName }
        XCTAssertEqual(customViews.count, 1)
        let customView = try XCTUnwrap(customViews.first)
        let documents = hitchDocuments(for: customView)

        let reconstructed = try XCTUnwrap(reconstructHitches(from: documents))
        XCTAssertFalse(reconstructed.isActive)
        XCTAssertGreaterThan(reconstructed.slowFramesCount, 0)

        // Oracle mutation controls: no payload cannot invent a hitch, and an appended explicit
        // empty final delta clears an earlier hitch instead of preserving it.
        let missingPayloads = documents.map { document in
            var document = document
            document.slowFramesCount = nil
            return document
        }
        XCTAssertFalse(hasStoppedHitches(in: missingPayloads))

        let finalVersion = try XCTUnwrap(documents.map(\.documentVersion).max())
        let finalDocument = try XCTUnwrap(documents.first { $0.documentVersion == finalVersion })
        let explicitEmptyFinalDelta = documents + [
            HitchDocument(
                kind: .delta,
                sessionID: finalDocument.sessionID,
                viewID: finalDocument.viewID,
                documentVersion: finalVersion + 1,
                isActive: false,
                slowFramesCount: 0
            )
        ]
        XCTAssertFalse(hasStoppedHitches(in: explicitEmptyFinalDelta))
    }

    private struct HitchDocument {
        enum Kind: Equatable {
            case full
            case delta
        }

        let kind: Kind
        let sessionID: String
        let viewID: String
        let documentVersion: Int64
        let isActive: Bool?
        var slowFramesCount: Int?
    }

    private struct ReconstructedHitches {
        let isActive: Bool
        let slowFramesCount: Int
    }

    private func hitchDocuments(for view: RUMSessionMatcher.View) -> [HitchDocument] {
        view.viewEvents.map {
            HitchDocument(
                kind: .full,
                sessionID: $0.session.id,
                viewID: $0.view.id,
                documentVersion: $0.dd.documentVersion,
                isActive: $0.view.isActive,
                slowFramesCount: $0.view.slowFrames?.count
            )
        } + view.viewUpdateEvents.map {
            HitchDocument(
                kind: .delta,
                sessionID: $0.session.id,
                viewID: $0.view.id,
                documentVersion: $0.dd.documentVersion,
                isActive: $0.view.isActive,
                slowFramesCount: $0.view.slowFrames?.count
            )
        }
    }

    private func reconstructHitches(from documents: [HitchDocument]) -> ReconstructedHitches? {
        let ordered = documents.sorted { $0.documentVersion < $1.documentVersion }
        guard
            let initial = ordered.first,
            initial.kind == .full,
            initial.documentVersion == 1,
            !initial.sessionID.isEmpty,
            !initial.viewID.isEmpty,
            let initialIsActive = initial.isActive,
            ordered.dropFirst().allSatisfy({ $0.kind == .delta }),
            ordered.last?.kind == .delta,
            Set(ordered.map(\.sessionID)).count == 1,
            Set(ordered.map(\.viewID)).count == 1,
            zip(ordered, ordered.dropFirst()).allSatisfy({ $0.documentVersion < $1.documentVersion })
        else {
            return nil
        }

        var isActive = initialIsActive
        var slowFramesCount = initial.slowFramesCount

        for delta in ordered.dropFirst() {
            if let deltaIsActive = delta.isActive {
                isActive = deltaIsActive
            }
            if let deltaSlowFramesCount = delta.slowFramesCount {
                slowFramesCount = deltaSlowFramesCount
            }
        }

        return ReconstructedHitches(isActive: isActive, slowFramesCount: slowFramesCount ?? 0)
    }

    private func hasStoppedHitches(in documents: [HitchDocument]) -> Bool {
        guard let reconstructed = reconstructHitches(from: documents) else {
            return false
        }

        return !reconstructed.isActive && reconstructed.slowFramesCount > 0
    }
}
