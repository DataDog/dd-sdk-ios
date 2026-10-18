/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@_spi(Internal)
@testable import DatadogInternal

class DatadogCoreProtocolTests: XCTestCase {
    func testCustomAndNOPScopesDoNotRequireHandoffCapability() {
        XCTAssertNil(RUMContextHandoff.owner(in: FeatureScopeMock()))
        XCTAssertNil(RUMContextHandoff.owner(in: NOPFeatureScope()))
        XCTAssertNil(RUMContextHandoff.owner(in: PassthroughCoreMock()))
        XCTAssertNil(RUMContextHandoff.owner(in: NOPDatadogCore()))
    }

    func testInvalidatingAnOwnerPreservesAnotherLifetime() {
        let first = RUMContextHandoff.Owner()
        let second = RUMContextHandoff.Owner()

        first.invalidate()
        first.invalidate()

        XCTAssertFalse(first.isValid)
        XCTAssertTrue(second.isValid)
    }

    func testAcceptedActionReceiptCannotAdoptASubsequentAction() {
        let owner = RUMContextHandoff.Owner()
        let context = receiptContext(actionID: "prior-action")
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: context)
        let value = receiptValue(context: context, receipt: receipt)
        XCTAssertNil(value.resolvedRUMContext(for: owner)?.userActionID)

        receipt.accept(sessionID: context.sessionID, viewID: "view-a", actionID: "original-action")
        receipt.accept(sessionID: context.sessionID, viewID: "view-a", actionID: "later-action")
        receipt.reject()
        let result = value.resolvedRUMContext(for: owner)
        XCTAssertEqual(result?.userActionID, "original-action")
        XCTAssertEqual(result?.viewID, context.viewID)
        XCTAssertEqual(result?.viewName, context.viewName)
        XCTAssertEqual(result?.viewServerTimeOffset, context.viewServerTimeOffset)
        XCTAssertEqual(result?.sessionSampler, context.sessionSampler)
    }

    func testRejectedActionReceiptDoesNotBorrowAPriorOrSubsequentAction() {
        let owner = RUMContextHandoff.Owner()
        let context = receiptContext(actionID: "prior-action")
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: context)
        receipt.reject()
        receipt.accept(sessionID: context.sessionID, viewID: "view-a", actionID: "later-action")
        let result = receiptValue(context: context, receipt: receipt).resolvedRUMContext(for: owner)
        XCTAssertEqual(result?.viewID, "view-a")
        XCTAssertNil(result?.userActionID)
    }

    func testActionReceiptRejectsForeignOwnerSessionAndView() {
        let owner = RUMContextHandoff.Owner()
        let otherOwner = RUMContextHandoff.Owner()
        let context = receiptContext(actionID: nil)
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: context)
        receipt.accept(sessionID: context.sessionID, viewID: "view-a", actionID: "original-action")
        XCTAssertNil(receipt.actionID(for: otherOwner, sessionID: context.sessionID, viewID: context.viewID))
        XCTAssertNil(receipt.actionID(for: owner, sessionID: "other-session", viewID: context.viewID))
        XCTAssertNil(receipt.actionID(for: owner, sessionID: context.sessionID, viewID: "other-view"))
        owner.invalidate()
        XCTAssertNil(receiptValue(context: context, receipt: receipt).resolvedRUMContext(for: owner))
    }

    func testMismatchedActionAcceptanceCannotBeReplacedByALaterValidAction() {
        let owner = RUMContextHandoff.Owner()
        let context = receiptContext(actionID: nil)
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: context)
        receipt.accept(sessionID: "other-session", viewID: "view-a", actionID: "foreign-action")
        receipt.accept(sessionID: context.sessionID, viewID: "view-a", actionID: "later-action")
        XCTAssertNil(receipt.actionID(for: owner, sessionID: context.sessionID, viewID: context.viewID))
    }

    func testUnprocessedActionReceiptPreservesAuthoritativeAbsence() {
        let owner = RUMContextHandoff.Owner()
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: nil)
        receipt.accept(sessionID: "session-a", viewID: "view-a", actionID: "later-action")
        XCTAssertNil(receiptValue(context: nil, receipt: receipt).resolvedRUMContext(for: owner))
        let context = receiptContext(actionID: "prior-action")
        let pending = receiptValue(context: context, receipt: nil)
        XCTAssertNil(pending.resolvedRUMContext(for: owner)?.userActionID)
    }

    private func requireCaptureScope() throws {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            return
        }
        #endif
        throw XCTSkip("Consumer capture requires iOS 27")
    }

    func testInvalidatedCaptureOwnerPreservesAuthoritativeAbsence() throws {
        try requireCaptureScope()
        let owner = RUMContextHandoff.Owner()
        try RUMContextHandoff.withValue(receiptValue(context: receiptContext(actionID: nil), receipt: nil), for: owner) {
            owner.invalidate()
            XCTAssertNil(RUMContextHandoff.current(for: owner))
            let captured = try XCTUnwrap(RUMContextHandoff.captureValue(for: owner))
            XCTAssertNil(captured.rumContext)
            XCTAssertNil(captured.sceneIdentifier)
            XCTAssertNil(captured.actionReceipt)
            XCTAssertNil(captured.resolvedRUMContext(for: owner))
        }
        XCTAssertNotNil(RUMContextHandoff.captureValue(for: owner))
    }

    func testCaptureRetainsTheRawReceiptUntilActionAcceptance() throws {
        try requireCaptureScope()
        let owner = RUMContextHandoff.Owner()
        let context = receiptContext(actionID: "prior-action")
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: context)
        let captured = try RUMContextHandoff.withValue(receiptValue(context: context, receipt: receipt), for: owner) {
            try XCTUnwrap(RUMContextHandoff.captureValue(for: owner))
        }
        XCTAssertTrue(captured.actionReceipt === receipt)
        XCTAssertEqual(captured.rumContext?.userActionID, "prior-action")
        XCTAssertNil(captured.resolvedRUMContext(for: owner)?.userActionID)
        receipt.accept(sessionID: context.sessionID, viewID: "view-a", actionID: "original-action")
        XCTAssertEqual(captured.resolvedRUMContext(for: owner)?.userActionID, "original-action")
        XCTAssertEqual(captured.resolvedRUMContext(for: owner)?.viewID, "view-a")
    }

    func testCaptureKeepsAValidNilBindingDistinctFromNoBinding() throws {
        try requireCaptureScope()
        let owner = RUMContextHandoff.Owner()
        XCTAssertNil(RUMContextHandoff.captureValue(for: owner))
        try RUMContextHandoff.withValue(receiptValue(context: nil, receipt: nil), for: owner) {
            let captured = try XCTUnwrap(RUMContextHandoff.captureValue(for: owner))
            XCTAssertNil(captured.rumContext)
            XCTAssertEqual(captured.sceneIdentifier, "scene-a")
            XCTAssertTrue(captured.hasPendingUserAction)
        }
        XCTAssertNil(RUMContextHandoff.captureValue(for: owner))
    }

    func testAbsentAndForeignCaptureOwnersPreserveLegacyFallback() throws {
        try requireCaptureScope()
        let owner = RUMContextHandoff.Owner()
        let foreign = RUMContextHandoff.Owner()
        RUMContextHandoff.withValue(receiptValue(context: receiptContext(actionID: nil), receipt: nil), for: owner) {
            XCTAssertNil(RUMContextHandoff.captureValue(for: nil))
            XCTAssertNil(RUMContextHandoff.captureValue(for: foreign))
        }
    }

    private func receiptContext(actionID: String?) -> RUMCoreContext {
        RUMCoreContext(
            applicationID: "application",
            sessionID: "session-a",
            sessionSampler: DeterministicSampler(seed: 42, samplingRate: 100),
            viewID: "view-a",
            userActionID: actionID,
            viewServerTimeOffset: 0.25,
            viewPath: "path-a",
            viewName: "View A"
        )
    }

    private func receiptValue(context: RUMCoreContext?, receipt: RUMContextHandoff.ActionReceipt?) -> RUMContextHandoff.CurrentValue {
        RUMContextHandoff.CurrentValue(
            rumContext: context,
            sceneIdentifier: "scene-a",
            hasPendingUserAction: true,
            excludedUserActionID: context?.userActionID,
            actionReceipt: receipt
        )
    }

    func testSendMessageExtension() {
        // Given
        let receiver = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        core.send(message: .payload("value"))

        // Then
        XCTAssertEqual(
            receiver.messages.last?.asPayload as? String, "value", "DatadogCoreProtocol.send(message:) should forward message"
        )
    }

    func testAdditionalContextExtension() throws {
        // Given
        let core = PassthroughCoreMock()

        struct MyContext: AdditionalContext, Equatable {
            static let key = "my-context"
            let value: String
        }

        // When
        core.set(context: MyContext(value: "value"))

        // Then
        XCTAssertEqual(core.context.additionalContext(ofType: MyContext.self), MyContext(value: "value"))

        // When
        core.removeContext(ofType: MyContext.self)

        // Then
        XCTAssertNil(core.context.additionalContext(ofType: MyContext.self))
    }
}
