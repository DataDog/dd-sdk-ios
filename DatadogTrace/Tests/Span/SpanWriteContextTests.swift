/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogTrace

class SpanWriteContextTests: XCTestCase {
    private struct OtherFeatureContext: AdditionalContext {
        static let key = "other-feature"
        let value: String
    }

    private let featureScope = FeatureScopeMock()

    @MainActor
    func testWhenRequestingSpanWriteContext_itProvidesInitialCoreContext() {
        let retrieveContext = expectation(description: "provide core context")

        var initialContext: DatadogContext = .mockRandom()
        initialContext.set(additionalContext: RUMCoreContext.mockRandom())
        featureScope.contextMock = initialContext

        // Given
        let writer = LazySpanWriteContext(featureScope: featureScope)

        // When
        featureScope.contextMock = .mockRandom()

        writer.spanWriteContext { providedContext, _ in
            // Then
            DDAssertReflectionEqual(providedContext, initialContext)
            retrieveContext.fulfill()
        }

        waitForExpectations(timeout: 0.5)
    }

    @MainActor
    func testWhenRemovingRUMContext_itPreservesOtherInitialContext() {
        let retrieveContext = expectation(description: "provide context without RUM ownership")
        var expectedContext: DatadogContext = .mockRandom()
        expectedContext.set(additionalContext: OtherFeatureContext(value: "initial"))
        var initialContext = expectedContext
        initialContext.set(additionalContext: RUMCoreContext.mockRandom())
        featureScope.contextMock = initialContext
        let writer = LazySpanWriteContext(featureScope: featureScope, rumContextOverride: .remove)
        let currentContext: DatadogContext = .mockRandom()
        featureScope.contextMock = currentContext

        writer.spanWriteContext { providedContext, _ in
            XCTAssertNil(providedContext.additionalContext(ofType: RUMCoreContext.self))
            DDAssertReflectionEqual(providedContext, expectedContext)
            retrieveContext.fulfill()
        }

        waitForExpectations(timeout: 0.5)
        DDAssertReflectionEqual(featureScope.contextMock, currentContext)
    }

    @MainActor
    func testWhenReplacingRUMContext_itPreservesOtherInitialContext() {
        let retrieveContext = expectation(description: "provide context with request-time RUM ownership")
        let requestRUMContext: RUMCoreContext = .mockRandom()
        var expectedContext: DatadogContext = .mockRandom()
        expectedContext.set(additionalContext: OtherFeatureContext(value: "initial"))
        expectedContext.set(additionalContext: requestRUMContext)
        var initialContext = expectedContext
        initialContext.set(additionalContext: RUMCoreContext.mockRandom())
        featureScope.contextMock = initialContext
        let writer = LazySpanWriteContext(featureScope: featureScope, rumContextOverride: .replace(requestRUMContext))
        let currentContext: DatadogContext = .mockRandom()
        featureScope.contextMock = currentContext

        writer.spanWriteContext { providedContext, _ in
            XCTAssertEqual(providedContext.additionalContext(ofType: RUMCoreContext.self), requestRUMContext)
            DDAssertReflectionEqual(providedContext, expectedContext)
            retrieveContext.fulfill()
        }

        waitForExpectations(timeout: 0.5)
        DDAssertReflectionEqual(featureScope.contextMock, currentContext)
    }

    func testWhenWritingEvent_itDoesNotBypassConsent() {
        // Given
        let writer = LazySpanWriteContext(featureScope: featureScope)

        // When
        writer.spanWriteContext { _, writer in
            writer.write(value: SpanEvent.mockAny())
        }

        // Then
        XCTAssertEqual(featureScope.eventsWritten(ofType: SpanEvent.self, withBypassConsent: false).count, 1)
        XCTAssertEqual(featureScope.eventsWritten(ofType: SpanEvent.self, withBypassConsent: true).count, 0)
    }
}

extension SpanWriteContextTests {
    func testCapturedWriterResolvesOriginalActionAtDeferredDeliveryAndPreservesOtherContext() {
        let owner = RUMContextHandoff.Owner()
        let captured = capturedWriterRUMContext()
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
        let value = RUMContextHandoff.CurrentValue(
            rumContext: captured,
            sceneIdentifier: "scene-a",
            hasPendingUserAction: true,
            excludedUserActionID: captured.userActionID,
            actionReceipt: receipt
        )
        var initialContext: DatadogContext = .mockRandom()
        initialContext.set(additionalContext: capturedWriterRUMContext(sessionID: "session-b", viewID: "view-b", actionID: "prior-delivery-action"))
        XCTAssertEqual(initialContext.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-b")
        XCTAssertEqual(initialContext.additionalContext(ofType: RUMCoreContext.self)?.userActionID, "prior-delivery-action")
        let scope = FeatureScopeMock(context: initialContext, deferEventWriteContext: true)
        let writer = CapturedRUMSpanWriteContext(
            original: LazySpanWriteContext(featureScope: scope),
            owner: owner,
            value: value,
            sessionOwnership: .request(captured.sessionID)
        )
        var calls = 0
        writer.spanWriteContext { provided, _ in
            var expected = initialContext
            expected.set(additionalContext: value.resolvedRUMContext(for: owner))
            DDAssertReflectionEqual(provided, expected)
            XCTAssertEqual(provided.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-a")
            XCTAssertEqual(provided.additionalContext(ofType: RUMCoreContext.self)?.userActionID, "original-action")
            calls += 1
        }
        XCTAssertEqual(calls, 0)
        receipt.accept(sessionID: captured.sessionID, viewID: "view-a", actionID: "original-action")
        receipt.accept(sessionID: captured.sessionID, viewID: "view-a", actionID: "subsequent-action")
        var deliveredContext: DatadogContext = .mockRandom()
        deliveredContext.set(additionalContext: capturedWriterRUMContext(sessionID: "session-c", viewID: "view-c", actionID: "later-delivery-action"))
        XCTAssertEqual(deliveredContext.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-c")
        XCTAssertEqual(deliveredContext.additionalContext(ofType: RUMCoreContext.self)?.userActionID, "later-delivery-action")
        scope.contextMock = deliveredContext
        scope.flushDeferredEventWriteContexts()
        XCTAssertEqual(calls, 1)
    }

    func testCapturedWriterOmitsRejectedOrUnresolvedActionWithoutBorrowingDeliveryAction() {
        for rejected in [false, true] {
            let owner = RUMContextHandoff.Owner()
            let captured = capturedWriterRUMContext()
            let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
            if rejected { receipt.reject() }
            let value = RUMContextHandoff.CurrentValue(
                rumContext: captured,
                sceneIdentifier: "scene-a",
                hasPendingUserAction: true,
                excludedUserActionID: captured.userActionID,
                actionReceipt: receipt
            )
            var initialContext: DatadogContext = .mockRandom()
            initialContext.set(additionalContext: capturedWriterRUMContext(sessionID: "session-b", viewID: "view-b", actionID: "prior-delivery-action"))
            XCTAssertEqual(initialContext.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-b")
            XCTAssertEqual(initialContext.additionalContext(ofType: RUMCoreContext.self)?.userActionID, "prior-delivery-action")
            let scope = FeatureScopeMock(context: initialContext, deferEventWriteContext: true)
            let writer = CapturedRUMSpanWriteContext(
                original: LazySpanWriteContext(featureScope: scope),
                owner: owner,
                value: value,
                sessionOwnership: .request(captured.sessionID)
            )
            var calls = 0
            writer.spanWriteContext { provided, _ in
                var expected = initialContext
                expected.set(additionalContext: value.resolvedRUMContext(for: owner))
                DDAssertReflectionEqual(provided, expected)
                XCTAssertEqual(provided.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-a")
                XCTAssertNil(provided.additionalContext(ofType: RUMCoreContext.self)?.userActionID)
                calls += 1
            }
            var deliveredContext: DatadogContext = .mockRandom()
            deliveredContext.set(additionalContext: capturedWriterRUMContext(sessionID: "session-c", viewID: "view-c", actionID: "later-delivery-action"))
            XCTAssertEqual(deliveredContext.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-c")
            XCTAssertEqual(deliveredContext.additionalContext(ofType: RUMCoreContext.self)?.userActionID, "later-delivery-action")
            scope.contextMock = deliveredContext
            scope.flushDeferredEventWriteContexts()
            XCTAssertEqual(calls, 1)
        }
    }

    func testCapturedWriterOmitsMissingUnequalInvalidAndAuthoritativelyAbsentOwnership() {
        for kind in ["missing-session", "unequal-session", "invalid-owner", "captured-nil"] {
            let owner = RUMContextHandoff.Owner()
            let captured = capturedWriterRUMContext()
            let value = RUMContextHandoff.CurrentValue(
                rumContext: kind == "captured-nil" ? nil : captured,
                sceneIdentifier: "scene-a",
                hasPendingUserAction: false,
                excludedUserActionID: nil
            )
            var initialContext: DatadogContext = .mockRandom()
            initialContext.set(additionalContext: capturedWriterRUMContext(sessionID: "session-b", viewID: "view-b", actionID: "prior-delivery-action"))
            XCTAssertEqual(initialContext.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-b")
            XCTAssertEqual(initialContext.additionalContext(ofType: RUMCoreContext.self)?.userActionID, "prior-delivery-action")
            let scope = FeatureScopeMock(context: initialContext, deferEventWriteContext: true)
            let sessionID = kind == "missing-session" ? nil : (kind == "unequal-session" ? "session-b" : captured.sessionID)
            let writer = CapturedRUMSpanWriteContext(
                original: LazySpanWriteContext(featureScope: scope),
                owner: owner,
                value: value,
                sessionOwnership: .request(sessionID)
            )
            var calls = 0
            writer.spanWriteContext { provided, _ in
                var expected = initialContext
                expected.set(additionalContext: Optional<RUMCoreContext>.none)
                DDAssertReflectionEqual(provided, expected)
                XCTAssertNil(provided.additionalContext(ofType: RUMCoreContext.self), kind)
                calls += 1
            }
            if kind == "invalid-owner" { owner.invalidate() }
            var deliveredContext: DatadogContext = .mockRandom()
            deliveredContext.set(additionalContext: capturedWriterRUMContext(sessionID: "session-c", viewID: "view-c", actionID: "later-delivery-action"))
            XCTAssertEqual(deliveredContext.additionalContext(ofType: RUMCoreContext.self)?.viewID, "view-c")
            XCTAssertEqual(deliveredContext.additionalContext(ofType: RUMCoreContext.self)?.userActionID, "later-delivery-action")
            scope.contextMock = deliveredContext
            scope.flushDeferredEventWriteContexts()
            XCTAssertEqual(calls, 1, kind)
        }
    }

    private func capturedWriterRUMContext(sessionID: String = "session-a", viewID: String = "view-a", actionID: String = "prior-action") -> RUMCoreContext {
        RUMCoreContext(
            applicationID: "application-a",
            sessionID: sessionID,
            sessionSampler: DeterministicSampler(seed: 42, samplingRate: 100),
            viewID: viewID,
            userActionID: actionID,
            viewServerTimeOffset: 0.25,
            viewPath: "path-a",
            viewName: "View A"
        )
    }
}
