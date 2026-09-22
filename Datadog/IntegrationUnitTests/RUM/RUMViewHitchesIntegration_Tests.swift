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
/// Assertions fold full baselines and ordered deltas. A full event replaces the baseline;
/// fields omitted from a delta keep their previous values.
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
        for document in documents {
            XCTAssertNil(document.slowFramesCount, "Disabled tracking must omit slow_frames")
        }

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

    func testReconstructHitches_whenFullDocumentsRecur_itReplacesTheBaseline() throws {
        func document(
            _ version: Int64,
            _ kind: HitchDocument.Kind,
            isActive: Bool? = nil,
            slowFramesCount: Int? = nil
        ) -> HitchDocument {
            HitchDocument(
                kind: kind,
                sessionID: "session",
                viewID: "view",
                documentVersion: version,
                isActive: isActive,
                slowFramesCount: slowFramesCount
            )
        }

        let documents = [
            document(1, .full, isActive: true, slowFramesCount: 3),
            document(2, .delta),
            document(3, .delta),
            document(4, .delta),
            document(5, .delta),
            document(6, .delta),
            document(7, .full, isActive: true),
            document(8, .delta)
        ]
        let afterBaseline = try XCTUnwrap(reconstructHitches(from: documents))
        XCTAssertTrue(afterBaseline.isActive)
        XCTAssertEqual(afterBaseline.slowFramesCount, 0)

        let withFullStop = documents + [document(9, .full, isActive: false, slowFramesCount: 2)]
        let stopped = try XCTUnwrap(reconstructHitches(from: withFullStop))
        XCTAssertFalse(stopped.isActive)
        XCTAssertEqual(stopped.slowFramesCount, 2)
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
            Set(ordered.map(\.sessionID)).count == 1,
            Set(ordered.map(\.viewID)).count == 1,
            zip(ordered, ordered.dropFirst()).allSatisfy({ $0.documentVersion < $1.documentVersion })
        else {
            return nil
        }

        var isActive = initialIsActive
        var slowFramesCount = initial.slowFramesCount

        for document in ordered.dropFirst() {
            switch document.kind {
            case .full:
                guard let baselineIsActive = document.isActive else {
                    return nil
                }
                isActive = baselineIsActive
                slowFramesCount = document.slowFramesCount
            case .delta:
                if let deltaIsActive = document.isActive {
                    isActive = deltaIsActive
                }
                if let deltaSlowFramesCount = document.slowFramesCount {
                    slowFramesCount = deltaSlowFramesCount
                }
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
