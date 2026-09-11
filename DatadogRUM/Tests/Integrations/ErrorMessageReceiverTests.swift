/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import TestUtilities

@testable import DatadogRUM

class ErrorMessageReceiverTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private var receiver: ErrorMessageReceiver! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        receiver = ErrorMessageReceiver(
            featureScope: featureScope,
            monitor: Monitor(
                dependencies: .mockWith(featureScope: featureScope),
                dateProvider: SystemDateProvider()
            )
        )
    }

    override func tearDown() {
        receiver = nil
    }

    func testReceivePartialLogError() throws {
        // When
        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "logger",
                type: nil,
                stack: nil,
                attributes: [:],
                binaryImages: nil
            )
        )

        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        let event: RUMErrorEvent = try XCTUnwrap(featureScope.eventsWritten().last, "It should send error")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.source, .logger)
    }

    func testReceiveCompleteLogError() throws {
        // Given
        let mockAttribute: String = .mockRandom()
        let mockBinaryImage: BinaryImage = .mockRandom()
        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "custom",
                type: "type-test",
                stack: "stack-test",
                attributes: [
                    "any-key": mockAttribute
                ],
                binaryImages: [mockBinaryImage]
            )
        )

        // When
        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        let event: RUMErrorEvent = try XCTUnwrap(featureScope.eventsWritten().last, "It should send error")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.type, "type-test")
        XCTAssertEqual(event.error.stack, "stack-test")
        XCTAssertEqual(event.error.source, .custom)
        XCTAssertNotNil(event.error.binaryImages)
        XCTAssertEqual(event.error.binaryImages?.count, 1)
        if let image = event.error.binaryImages?.first {
            XCTAssertEqual(mockBinaryImage.libraryName, image.name)
            XCTAssertEqual(mockBinaryImage.uuid, image.uuid)
            XCTAssertEqual(mockBinaryImage.architecture, image.arch)
            XCTAssertEqual(mockBinaryImage.isSystemLibrary, image.isSystem)
            XCTAssertEqual(mockBinaryImage.loadAddress, image.loadAddress)
            XCTAssertEqual(mockBinaryImage.maxAddress, image.maxAddress)
        }

        XCTAssertEqual(event.context?.contextInfo["any-key"] as? String, mockAttribute)
    }

    func testReceiveLogErrorWithCapturedView_itTargetsThatViewAndRemovesBusMetadata() throws {
        // Given
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        receiver.monitor.process(
            command: RUMStartViewCommand.mockWith(
                name: "View A",
                path: "View A",
                target: .scene(sceneA)
            )
        )
        let viewAID = try XCTUnwrap(
            receiver.monitor.applicationScope.activeSession?.activeView?.viewUUID
        )
        let actionID = UUID()
        receiver.monitor.process(
            command: RUMStartViewCommand.mockWith(
                name: "View B",
                path: "View B",
                target: .scene(sceneB)
            )
        )

        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "logger",
                type: nil,
                stack: nil,
                attributes: [
                    "customer-key": "customer-value",
                    "_dd.internal.rum.error.target_view_id": viewAID.toRUMDataFormat,
                    "_dd.internal.rum.error.target_action_id": actionID.uuidString,
                    "_dd.internal.rum.error.context_captured": true
                ],
                binaryImages: nil
            )
        )

        // When
        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result)
        let event: RUMErrorEvent = try XCTUnwrap(featureScope.eventsWritten().last)
        XCTAssertEqual(event.view.id, viewAID.toRUMDataFormat)
        XCTAssertEqual(event.view.name, "View A")
        XCTAssertEqual(event.action?.id, .string(value: actionID.uuidString.lowercased()))
        XCTAssertEqual(event.context?.contextInfo["customer-key"] as? String, "customer-value")
        XCTAssertNil(event.context?.contextInfo["_dd.internal.rum.error.target_view_id"])
        XCTAssertNil(event.context?.contextInfo["_dd.internal.rum.error.target_action_id"])
        XCTAssertNil(event.context?.contextInfo["_dd.internal.rum.error.context_captured"])
    }

    func testReceiveLogErrorWithExplicitlyEmptyCapturedAction_itDoesNotUseCurrentAction() throws {
        receiver.monitor.process(command: RUMStartViewCommand.mockWith(name: "View", path: "View"))
        let viewID = try XCTUnwrap(receiver.monitor.applicationScope.activeSession?.activeView?.viewUUID)
        receiver.monitor.process(
            command: RUMAddUserActionCommand.mockWith(actionType: .tap, name: "Current action")
        )

        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "logger",
                type: nil,
                stack: nil,
                attributes: [
                    "_dd.internal.rum.error.target_view_id": viewID.toRUMDataFormat,
                    "_dd.internal.rum.error.context_captured": true
                ],
                binaryImages: nil
            )
        )

        XCTAssertTrue(receiver.receive(message: message, from: NOPDatadogCore()))

        let event: RUMErrorEvent = try XCTUnwrap(featureScope.eventsWritten().last)
        XCTAssertNil(event.action)
    }

    func testReceiveLogErrorWithCapturedSceneButNoViewSnapshot_itDoesNotUseAnotherScene() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        receiver.monitor.process(
            command: RUMStartViewCommand.mockWith(
                name: "View A",
                path: "View A",
                target: .scene(sceneA)
            )
        )
        receiver.monitor.process(
            command: RUMStartViewCommand.mockWith(
                name: "View B",
                path: "View B",
                target: .scene(sceneB)
            )
        )

        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "logger",
                type: nil,
                stack: nil,
                attributes: [
                    "_dd.internal.rum.error.target_scene_id": sceneA.rawValue,
                    "_dd.internal.rum.error.context_captured": true
                ],
                binaryImages: nil
            )
        )

        XCTAssertTrue(receiver.receive(message: message, from: NOPDatadogCore()))

        let event: RUMErrorEvent = try XCTUnwrap(featureScope.eventsWritten().last)
        XCTAssertEqual(event.view.name, "View A")
        XCTAssertNil(event.action)
        XCTAssertNil(event.context?.contextInfo["_dd.internal.rum.error.target_scene_id"])
    }

    func testReceiveLogErrorWithCapturedAbsenceAndNoScene_itDropsInsteadOfUsingRepresentative() {
        receiver.monitor.process(command: RUMStartViewCommand.mockWith(name: "View", path: "View"))
        let initialErrorCount = featureScope.eventsWritten(ofType: RUMErrorEvent.self).count
        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "logger",
                type: nil,
                stack: nil,
                attributes: ["_dd.internal.rum.error.context_captured": true],
                binaryImages: nil
            )
        )

        XCTAssertTrue(receiver.receive(message: message, from: NOPDatadogCore()))
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, initialErrorCount)
    }
}
