/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class RUMFeatureOperationManagerTests: XCTestCase {
    private var manager: RUMFeatureOperationManager! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockParent: RUMContextProviderMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockDependencies: RUMScopeDependencies! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockWriter: FileWriterMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var mockContext: DatadogContext! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        mockParent = RUMContextProviderMock()
        mockDependencies = RUMScopeDependencies.mockAny()
        mockWriter = FileWriterMock()
        mockContext = DatadogContext.mockAny()

        manager = RUMFeatureOperationManager(
            parent: mockParent,
            dependencies: mockDependencies
        )
    }

    override func tearDown() {
        manager = nil
        mockParent = nil
        mockDependencies = nil
        mockWriter = nil
        mockContext = nil
        super.tearDown()
    }

    // MARK: - Process Command Tests

    func testFeatureOperationCommand_CreatesVitalEvent() throws {
        // Given
        let command = RUMOperationStepVitalCommand.mockRandom()
        let view: RUMViewScope = .mockAny()

        // When
        manager.process(
            command,
            context: mockContext,
            writer: mockWriter,
            activeView: view
        )

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertNotNil(event)
        // Operation Step specific properties
        XCTAssertEqual(event.vital.type, .operationStep)
        XCTAssertEqual(event.vital.id, command.vitalId)
        XCTAssertEqual(event.vital.name, command.name)
        XCTAssertEqual(event.vital.operationKey, command.operationKey)
        XCTAssertEqual(event.vital.stepType, command.stepType)
        XCTAssertEqual(event.vital.failureReason, command.failureReason)
        XCTAssertEqual(event.view.id, view.viewUUID.toRUMDataFormat)
        XCTAssertEqual(event.view.url, view.viewPath)
        XCTAssertNil(event.vital.vitalDescription)
        XCTAssertNil(event.vital.duration)
        // Common properties
        XCTAssertNil(event.account)
        XCTAssertNil(event.buildId)
        XCTAssertNotNil(event.buildVersion)
        XCTAssertNil(event.ciTest)
        XCTAssertNotNil(event.connectivity)
        XCTAssertNil(event.container)
        XCTAssertNotNil(event.context)
        XCTAssertNotNil(event.ddtags)
        XCTAssertNotNil(event.device)
        XCTAssertNil(event.display)
        XCTAssertNotNil(event.os)
        XCTAssertNotNil(event.service)
        XCTAssertEqual(event.source, .ios)
        XCTAssertNil(event.synthetics)
        XCTAssertNil(event.usr)
        XCTAssertNotNil(event.version)
    }

    func testProcess_MultipleOperations_CreatesCorrectNumberOfEvents() {
        // Given
        let commandCount = Int.random(in: 1...10)
        let commands = Array(repeating: RUMOperationStepVitalCommand.mockRandom(), count: commandCount)
        let view: RUMViewScope = .mockAny()

        commands.forEach { command in
            manager.process(
                command,
                context: mockContext,
                writer: mockWriter,
                activeView: view
            )
        }

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, commands.count)

        for (index, operation) in commands.enumerated() {
            let event = vitalEvents[index]
            XCTAssertEqual(event.vital.type, .operationStep)
            XCTAssertEqual(event.vital.id, operation.vitalId)
            XCTAssertEqual(event.vital.name, operation.name)
            XCTAssertEqual(event.vital.operationKey, operation.operationKey)
            XCTAssertEqual(event.vital.stepType, operation.stepType)
            XCTAssertEqual(event.vital.failureReason, operation.failureReason)
            XCTAssertEqual(event.view.id, view.viewUUID.toRUMDataFormat)
            XCTAssertEqual(event.view.url, view.viewPath)
            XCTAssertNil(event.vital.vitalDescription)
            XCTAssertNil(event.vital.duration)
        }
    }

    // MARK: - Edge Cases Tests

    private let invalidNames = ["", " ", "\n", "\t", "   \n\t  "]
    func testProcess_OperationWithInvalidName_DoesNotCreateVitalEvent() {
        // Given
        for invalidName in invalidNames {
            let command = RUMOperationStepVitalCommand.mockWith(name: invalidName)

            // When
            manager.process(
                command,
                context: mockContext,
                writer: mockWriter,
                activeView: .mockAny()
            )
        }

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }

    func testProcess_OperationWithInvalidOperationKey_DoesNotCreateVitalEvent() {
        // Given
        for invalidOpKey in invalidNames {
            let command = RUMOperationStepVitalCommand.mockWith(name: .mockAny(), operationKey: invalidOpKey)

            // When
            manager.process(
                command,
                context: mockContext,
                writer: mockWriter,
                activeView: .mockAny()
            )
        }

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 0)
    }

    // MARK: Warning Logs Tests

    func testProcess_OperationUpdateWithoutStart_LogsWarning() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let operationName: String = .mockRandom()
        let stepType = [
            RUMVitalEvent.Vital.StepType.end,
            RUMVitalEvent.Vital.StepType.retry,
            RUMVitalEvent.Vital.StepType.update
        ].randomElement()!
        let command = RUMOperationStepVitalCommand.mockWith(
            name: operationName,
            operationKey: nil,
            stepType: stepType
        )

        // When
        manager.process(command, context: mockContext, writer: mockWriter, activeView: .mockAny())

        // Then
        let logMessage = try XCTUnwrap(dd.logger.warnLog?.message)
        XCTAssertEqual(logMessage, "`\(stepType.rawValue)` was called, but operation `\(operationName)` is currently not active. This may lead to a backend `instrumentation_error`. Make sure to call `startFeatureOperation(name:operationKey:attributes:)` first. Note that the SDK only tracks operations locally and not across sessions.")
    }

    func testProcess_OperationStartTwice_LogsWarning() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let operationName: String = .mockRandom()
        let operationKey: String = .mockAny()
        let startCommand1 = RUMOperationStepVitalCommand.mockWith(
            name: operationName,
            operationKey: operationKey,
            stepType: .start
        )
        let startCommand2 = RUMOperationStepVitalCommand.mockWith(
            name: operationName,
            operationKey: operationKey,
            stepType: .start
        )

        // When
        manager.process(startCommand1, context: mockContext, writer: mockWriter, activeView: .mockAny())
        manager.process(startCommand2, context: mockContext, writer: mockWriter, activeView: .mockAny())

        // Then
        let logMessage = try XCTUnwrap(dd.logger.warnLog?.message)
        XCTAssertEqual(logMessage, "Operation `\(operationName)` (key `\(operationKey)`) has already been started. This may result in the backend terminating the previous instance with an `auto_restart` failure. Note that the SDK only tracks operations locally and not across sessions.")
    }

    func testProcess_ValidOperationFlow_NoWarnings() {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let startCommand = RUMOperationStepVitalCommand.mockWith(stepType: .start)
        let endCommand = RUMOperationStepVitalCommand.mockWith(stepType: .end)

        // When
        manager.process(startCommand, context: mockContext, writer: mockWriter, activeView: .mockAny())
        manager.process(endCommand, context: mockContext, writer: mockWriter, activeView: .mockAny())

        // Then
        XCTAssertNil(dd.logger.warnLog)
    }

    // MARK: - Synthetics Test ID Tests

    func testProcess_WithSyntheticsTestId_IncludesSyntheticsInVitalEvent() throws {
        // Given
        let fakeSyntheticsTestId: String = .mockRandom()
        let fakeSyntheticsResultId: String = .mockRandom()
        let syntheticsTest = RUMSyntheticsTest(
            injected: nil,
            resultId: fakeSyntheticsResultId,
            testId: fakeSyntheticsTestId
        )

        mockDependencies = RUMScopeDependencies.mockWith(syntheticsTest: syntheticsTest)
        manager = RUMFeatureOperationManager(
            parent: mockParent,
            dependencies: mockDependencies
        )

        let command = RUMOperationStepVitalCommand.mockRandom()
        let view: RUMViewScope = .mockAny()

        // When
        manager.process(
            command,
            context: mockContext,
            writer: mockWriter,
            activeView: view
        )

        // Then
        let vitalEvents = mockWriter.events(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let event = try XCTUnwrap(vitalEvents.first)
        XCTAssertEqual(event.synthetics?.testId, fakeSyntheticsTestId)
        XCTAssertEqual(event.synthetics?.resultId, fakeSyntheticsResultId)
        XCTAssertEqual(event.synthetics?.injected, nil)
    }
}
