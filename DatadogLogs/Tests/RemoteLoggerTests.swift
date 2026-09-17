/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogLogs

class RemoteLoggerTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    // MARK: - Sending Error Message over Message Bus

    private struct ExpectedErrorMessage: Decodable {
        /// The Log error message
        let message: String
        /// The Log error type
        let type: String?
        /// The Log error stack
        let stack: String?
        /// The Log error stack
        let source: String
        /// The Log attributes
        let attributes: [String: AnyCodable]
        /// Binary images
        let binaryImages: [BinaryImage]?
    }

    func testWhenNonErrorLogged_itDoesNotPostsToMessageBus() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.info("Info message")

        // Then
        XCTAssertEqual(featureScope.messagesSent().count, 0)
    }

    func testWhenErrorLogged_itPostsToMessageBus() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.error("Error message")

        // Then
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertEqual(errorMessage.message, "Error message")
    }

    func testWhenAttributesContainIncludeBinaryImages_itPostsBinaryImagesToMessageBus() throws {
        let stubBacktrace: BacktraceReport = .mockRandom()
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock(backtrace: stubBacktrace)
        )

        // When
        logger.error("Information message", error: ErrorMock(), attributes: [CrossPlatformAttributes.includeBinaryImages: true])

        // Then
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        // This is removed because binary images are sent in the message, so the additional attribute isn't needed
        XCTAssertNil(errorMessage.attributes[CrossPlatformAttributes.includeBinaryImages])
        XCTAssertEqual(errorMessage.binaryImages?.count, stubBacktrace.binaryImages.count)
        for i in 0..<stubBacktrace.binaryImages.count {
            let logBacktrace = errorMessage.binaryImages![i]
            let errorBacktrace = stubBacktrace.binaryImages[i]
            XCTAssertEqual(logBacktrace.libraryName, errorBacktrace.libraryName)
            XCTAssertEqual(logBacktrace.uuid, errorBacktrace.uuid)
            XCTAssertEqual(logBacktrace.architecture, errorBacktrace.architecture)
            XCTAssertEqual(logBacktrace.isSystemLibrary, errorBacktrace.isSystemLibrary)
            XCTAssertEqual(logBacktrace.loadAddress, errorBacktrace.loadAddress)
            XCTAssertEqual(logBacktrace.maxAddress, errorBacktrace.maxAddress)
        }
    }

    func testWhenBinaryImagesGenerationFails_itReportsErrorToTelemetryAndOmitsBinaryImages() throws {
        // Given
        let generationError = ErrorMock("binary images generation failed")
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock(backtraceGenerationError: generationError)
        )

        // When
        logger.error("Information message", error: ErrorMock(), attributes: [CrossPlatformAttributes.includeBinaryImages: true])

        // Then
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertNil(errorMessage.binaryImages, "Binary images should be omitted when generation fails")
        XCTAssertNotNil(featureScope.telemetryMock.messages.firstError(), "The generation error should be reported to telemetry")
    }

    func testWhenErrorLogged_itPostsToMessageBus_withOtherCrossPlatformAttributesIntact() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        let mockFingerprint: String = .mockRandom()
        logger.error(
            "Error message",
            error: nil,
            attributes: [
                CrossPlatformAttributes.errorSourceType: "flutter",
                Logs.Attributes.errorFingerprint: mockFingerprint
            ]
        )

        // Then
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertEqual(errorMessage.attributes[CrossPlatformAttributes.errorSourceType] as? String, "flutter")
        XCTAssertEqual(errorMessage.attributes[Logs.Attributes.errorFingerprint] as? String, mockFingerprint)
    }

    func testWhenErrorLoggedFromInternal_itPostsToMessageBus_withSourceTypeInjected() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        let mockFingerprint: String = .mockRandom()
        logger._internal.log(
            level: .error,
            message: "Error message",
            errorKind: .mockAny(),
            errorMessage: .mockRandom(),
            stackTrace: .mockAny(),
            attributes: [
                CrossPlatformAttributes.errorSourceType: "flutter",
                Logs.Attributes.errorFingerprint: mockFingerprint
            ]
        )

        // Then
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertEqual(errorMessage.attributes[CrossPlatformAttributes.errorSourceType] as? String, "flutter")
        XCTAssertEqual(errorMessage.attributes[Logs.Attributes.errorFingerprint] as? String, mockFingerprint)
    }

    func testWhenCriticalLoggedFromInternal_itCallCompletion() throws {
        let completionExpectation = expectation(description: "Error processing completion")

        // Given
        let stubBacktrace: BacktraceReport = .mockRandom()

        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock(backtrace: stubBacktrace)
        )

        // When
        let message = String.mockRandom()
        logger._internal.critical(
            message: message,
            error: ErrorMock(),
            attributes: [CrossPlatformAttributes.includeBinaryImages: true],
            completionHandler: completionExpectation.fulfill
        )

        // Then
        wait(for: [completionExpectation], timeout: 0)
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.message, message)
        XCTAssertNil(log.attributes.userAttributes[CrossPlatformAttributes.includeBinaryImages])
        XCTAssertNotNil(log.error?.binaryImages)
        XCTAssertEqual(log.error?.binaryImages?.count, stubBacktrace.binaryImages.count)
        for i in 0..<stubBacktrace.binaryImages.count {
            let logBacktrace = log.error!.binaryImages![i]
            let errorBacktrace = stubBacktrace.binaryImages[i]
            XCTAssertEqual(logBacktrace.name, errorBacktrace.libraryName)
            XCTAssertEqual(logBacktrace.uuid, errorBacktrace.uuid)
            XCTAssertEqual(logBacktrace.arch, errorBacktrace.architecture)
            XCTAssertEqual(logBacktrace.isSystem, errorBacktrace.isSystemLibrary)
            XCTAssertEqual(logBacktrace.loadAddress, errorBacktrace.loadAddress)
            XCTAssertEqual(logBacktrace.maxAddress, errorBacktrace.maxAddress)
        }
    }

    // MARK: - Attributes

    func testWhenAddingAndRemovingLoggerAttributes_itSendsLogsWithCurrentAttributes() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.info("INFO message")

        logger.addAttribute(forKey: "attribute-1", value: "value A")
        logger.info("INFO message")

        logger.addAttribute(forKey: "attribute-2", value: "value B")
        logger.info("INFO message")

        logger.removeAttribute(forKey: "attribute-1")
        logger.info("INFO message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 4)
        XCTAssertEqual(logs[0].attributes.userAttributes.count, 0)
        XCTAssertEqual(logs[1].attributes.userAttributes as? [String: String], ["attribute-1": "value A"])
        XCTAssertEqual(logs[2].attributes.userAttributes as? [String: String], ["attribute-1": "value A", "attribute-2": "value B"])
        XCTAssertEqual(logs[3].attributes.userAttributes as? [String: String], ["attribute-2": "value B"])
    }

    func testGivenGlobalAttributeAvailable_whenSendingLog_itSendsLogWithGlobalAttribute() throws {
        let attributeKey = String.mockRandom()
        let attributeValue = String.mockRandom()

        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: SynchronizedAttributes(attributes: [attributeKey: attributeValue]),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.info("Information message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.userAttributes[attributeKey] as? String, attributeValue)
    }

    func testGivenGlobalAndLoggerAttributeAvailable_whenSendingLog_itSendsLogWithLoggerAttribute() throws {
        let attributeKey = String.mockRandom()
        let globalAttributeValue = String.mockRandom()
        let loggerAttributeValue = String.mockRandom()

        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: SynchronizedAttributes(attributes: [attributeKey: globalAttributeValue]),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        logger.addAttribute(forKey: attributeKey, value: loggerAttributeValue)

        // When
        logger.info("Information message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.userAttributes[attributeKey] as? String, loggerAttributeValue)
    }

    func testGivenGlobalAndLoggerAndLogAttributeAvailable_whenSendingLog_itSendsLogWithLogAttribute() throws {
        let attributeKey = String.mockRandom()
        let globalAttributeValue = String.mockRandom()
        let loggerAttributeValue = String.mockRandom()
        let logAttributeValue = String.mockRandom()

        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: SynchronizedAttributes(attributes: [attributeKey: globalAttributeValue]),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        logger.addAttribute(forKey: attributeKey, value: loggerAttributeValue)

        // When
        logger.info("Information message", attributes: [attributeKey: logAttributeValue])

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.userAttributes[attributeKey] as? String, logAttributeValue)
    }

    func testItSendsGlobalAttributesErrorAlongWithErrorLog() throws {
        let attributeKey = String.mockRandom()
        let attributeValue = String.mockRandom()

        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: SynchronizedAttributes(attributes: [attributeKey: attributeValue]),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.error("Error message")

        // Then
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertEqual(errorMessage.attributes[attributeKey] as? String, attributeValue)
    }

    func testWhenAttributesContainErrorFingerprint_itAddsItToTheLogEvent() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        let randomErrorFingerprint = String.mockRandom()
        logger.error("Information message", error: ErrorMock(), attributes: [Logs.Attributes.errorFingerprint: randomErrorFingerprint])

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.attributes.userAttributes[Logs.Attributes.errorFingerprint])
        XCTAssertEqual(log.error?.fingerprint, randomErrorFingerprint)
    }

    func testWhenAttributesContainIncludeBinaryImages_itAddsBinaryImagesToLogEvent() throws {
        let stubBacktrace: BacktraceReport = .mockRandom()
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock(backtrace: stubBacktrace)
        )

        // When
        logger.error("Information message", error: ErrorMock(), attributes: [CrossPlatformAttributes.includeBinaryImages: true])

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.attributes.userAttributes[CrossPlatformAttributes.includeBinaryImages])
        XCTAssertNotNil(log.error?.binaryImages)
        XCTAssertEqual(log.error?.binaryImages?.count, stubBacktrace.binaryImages.count)
        for i in 0..<stubBacktrace.binaryImages.count {
            let logBacktrace = log.error!.binaryImages![i]
            let errorBacktrace = stubBacktrace.binaryImages[i]
            XCTAssertEqual(logBacktrace.name, errorBacktrace.libraryName)
            XCTAssertEqual(logBacktrace.uuid, errorBacktrace.uuid)
            XCTAssertEqual(logBacktrace.arch, errorBacktrace.architecture)
            XCTAssertEqual(logBacktrace.isSystem, errorBacktrace.isSystemLibrary)
            XCTAssertEqual(logBacktrace.loadAddress, errorBacktrace.loadAddress)
            XCTAssertEqual(logBacktrace.maxAddress, errorBacktrace.maxAddress)
        }
    }

    // MARK: - Tags

    func testWhenAddingAndRemovingLoggerTags_itSendsLogsWithCurrentTags() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.info("INFO message")

        logger.add(tag: "tag1")
        logger.info("INFO message")

        logger.addTag(withKey: "tag2", value: "value")
        logger.info("INFO message")

        logger.remove(tag: "tag1")
        logger.info("INFO message")

        logger.removeTag(withKey: "tag2")
        logger.info("INFO message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 5)
        XCTAssertNil(logs[0].tags)
        XCTAssertEqual(logs[1].tags, ["tag1"])
        XCTAssertEqual(Set(logs[2].tags ?? []), Set(["tag2:value", "tag1"]))
        XCTAssertEqual(logs[3].tags, ["tag2:value"])
        XCTAssertNil(logs[4].tags)
    }

    // MARK: - RUM Integration

    func testWhenRUMIntegrationIsEnabled_itSendsLogWithRUMContext() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        let applicationID: String = .mockRandom()
        let sessionID: String = .mockRandom()
        let viewID: String = .mockRandom()
        let actionID: String = .mockRandom()

        // When
        featureScope.contextMock = .mockWith(
            additionalContext: [
                RUMCoreContext(
                    applicationID: applicationID,
                    sessionID: sessionID,
                    sessionSampler: .mockKeepAll(),
                    viewID: viewID,
                    userActionID: actionID
                )
            ]
        )

        logger.info("message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.internalAttributes?["application_id"] as? String, applicationID)
        XCTAssertEqual(log.attributes.internalAttributes?["session_id"] as? String, sessionID)
        XCTAssertEqual(log.attributes.internalAttributes?["view.id"] as? String, viewID)
        XCTAssertEqual(log.attributes.internalAttributes?["user_action.id"] as? String, actionID)
    }

    func testWhenErrorIsLoggedWithRUMIntegration_itSendsCapturedViewToRUMMessage() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        let viewID = UUID().uuidString.lowercased()
        let actionID = UUID().uuidString.lowercased()
        featureScope.contextMock = .mockWith(
            additionalContext: [
                RUMCoreContext(
                    applicationID: .mockRandom(),
                    sessionID: UUID().uuidString.lowercased(),
                    sessionSampler: .mockKeepAll(),
                    viewID: viewID,
                    userActionID: actionID
                )
            ]
        )

        // When
        logger.error("message")

        // Then
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.target_view_id"] as? String,
            viewID
        )
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.target_action_id"] as? String,
            actionID
        )
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.context_captured"] as? Bool,
            true
        )
        let log = try XCTUnwrap(featureScope.eventsWritten(ofType: LogEvent.self).first)
        XCTAssertNil(log.attributes.userAttributes["_dd.internal.rum.error.target_view_id"])
        XCTAssertNil(log.attributes.userAttributes["_dd.internal.rum.error.target_action_id"])
        XCTAssertNil(log.attributes.userAttributes["_dd.internal.rum.error.context_captured"])
    }

    func testWhenErrorIsLoggedWithRUMSessionButNoView_itKeepsLegacyOffViewRouting() throws {
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        featureScope.contextMock = .mockWith(
            additionalContext: [
                RUMCoreContext(
                    applicationID: UUID().uuidString.lowercased(),
                    sessionID: UUID().uuidString.lowercased(),
                    sessionSampler: .mockKeepAll()
                )
            ]
        )

        logger.error("message")

        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_view_id"])
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_scene_id"])
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.context_captured"])
    }

    func testWhenErrorIsLoggedWhileRUMViewIDIsEmpty_itKeepsLegacyOffViewRouting() throws {
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        featureScope.contextMock = .mockWith(
            additionalContext: [
                RUMCoreContext(
                    applicationID: UUID().uuidString.lowercased(),
                    sessionID: UUID().uuidString.lowercased(),
                    sessionSampler: .mockKeepAll(),
                    viewID: ""
                )
            ]
        )

        logger.error("message")

        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_view_id"])
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.context_captured"])
    }

    func testWhenCustomerAttributesCollideWithRUMRoutingMetadata_theyCannotControlMirrorRouting() throws {
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        let reservedAttributes: [String: Encodable] = [
            "_dd.internal.rum.error.target_view_id": UUID().uuidString,
            "_dd.internal.rum.error.target_action_id": UUID().uuidString,
            "_dd.internal.rum.error.target_scene_id": "customer-scene",
            "_dd.internal.rum.error.context_captured": true,
            "customer-key": "customer-value"
        ]

        logger.error("message", attributes: reservedAttributes)

        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_view_id"])
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_action_id"])
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_scene_id"])
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.context_captured"])
        XCTAssertEqual(errorMessage.attributes["customer-key"] as? String, "customer-value")

        let log = try XCTUnwrap(featureScope.eventsWritten(ofType: LogEvent.self).first)
        XCTAssertEqual(log.attributes.userAttributes["_dd.internal.rum.error.target_scene_id"] as? String, "customer-scene")
    }

    func testGivenForeignCoreDispatch_logAndMirroredErrorKeepConsumerOwnership() throws {
        let own: RUMCoreContext = .mockWith(sessionID: UUID(), viewID: UUID().uuidString, userActionID: UUID().uuidString)
        let origins: [RUMCoreContext?] = [
            .mockWith(applicationID: own.applicationID, sessionID: UUID(), viewID: UUID().uuidString),
            .mockWith(applicationID: "another-application", viewID: UUID().uuidString),
            nil
        ]
        for ownContext in [own, nil] {
            for origin in origins {
                let scope = FeatureScopeMock(context: .mockWith(additionalContext: ownContext.map { [$0] } ?? []))
                let logger = RemoteLogger(
                    featureScope: scope,
                    globalAttributes: .mockAny(),
                    configuration: .mockAny(),
                    dateProvider: RelativeDateProvider(),
                    rumContextIntegration: true,
                    activeSpanIntegration: false,
                    backtraceReporter: BacktraceReporterMock()
                )
                RUMContextHandoff.withValue(owner: .init(), rumContext: origin, sceneIdentifier: "foreign") {
                    logger.error("consumer error")
                }
                let log = try XCTUnwrap(scope.eventsWritten(ofType: LogEvent.self).first)
                XCTAssertEqual(log.attributes.internalAttributes?["application_id"] as? String, ownContext?.applicationID)
                XCTAssertEqual(log.attributes.internalAttributes?["session_id"] as? String, ownContext?.sessionID)
                XCTAssertEqual(log.attributes.internalAttributes?["view.id"] as? String, ownContext?.viewID)
                XCTAssertEqual(log.attributes.internalAttributes?["user_action.id"] as? String, ownContext?.userActionID)
                let mirror = try XCTUnwrap(scope.messagesSent().firstPayload as? RUMErrorMessage)
                XCTAssertEqual(mirror.attributes["_dd.internal.rum.error.target_view_id"] as? String, ownContext?.viewID)
                XCTAssertEqual(mirror.attributes["_dd.internal.rum.error.target_action_id"] as? String, ownContext?.userActionID)
                XCTAssertNil(mirror.attributes["_dd.internal.rum.error.target_scene_id"])
                XCTAssertEqual(mirror.attributes["_dd.internal.rum.error.context_captured"] as? Bool, ownContext == nil ? nil : true)
            }
        }
    }

    func testWhenErrorIsLoggedDuringSceneUIEvent_itUsesRequestLocalRUMContextForLogAndMirror() throws {
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        let representativeContext = RUMCoreContext(
            applicationID: UUID().uuidString.lowercased(),
            sessionID: UUID().uuidString.lowercased(),
            sessionSampler: .mockKeepAll(),
            viewID: UUID().uuidString.lowercased()
        )
        let sourceSceneContext = RUMCoreContext(
            applicationID: representativeContext.applicationID,
            sessionID: representativeContext.sessionID,
            sessionSampler: .mockKeepAll(),
            viewID: UUID().uuidString.lowercased(),
            userActionID: UUID().uuidString.lowercased()
        )
        featureScope.contextMock = .mockWith(additionalContext: [representativeContext])
        RUMContextHandoff.withValue(
            owner: RUMContextHandoff.owner(in: featureScope),
            rumContext: sourceSceneContext,
            sceneIdentifier: "scene-B"
        ) {
            logger.error("message")
        }

        let log = try XCTUnwrap(featureScope.eventsWritten(ofType: LogEvent.self).first)
        XCTAssertEqual(log.attributes.internalAttributes?["view.id"] as? String, sourceSceneContext.viewID)
        XCTAssertEqual(log.attributes.internalAttributes?["user_action.id"] as? String, sourceSceneContext.userActionID)
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.target_view_id"] as? String,
            sourceSceneContext.viewID
        )
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.target_action_id"] as? String,
            sourceSceneContext.userActionID
        )
    }

    func testWhenLoggedDuringUIEventWithoutSceneSnapshot_itDoesNotUseRepresentativeRUMContext() throws {
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        featureScope.contextMock = .mockWith(
            additionalContext: [
                RUMCoreContext(
                    applicationID: UUID().uuidString.lowercased(),
                    sessionID: UUID().uuidString.lowercased(),
                    sessionSampler: .mockKeepAll(),
                    viewID: UUID().uuidString.lowercased()
                )
            ]
        )
        let sceneIdentifier = "scene-B"
        RUMContextHandoff.withValue(owner: RUMContextHandoff.owner(in: featureScope), rumContext: nil, sceneIdentifier: sceneIdentifier) {
            logger.error("message")
        }

        let log = try XCTUnwrap(featureScope.eventsWritten(ofType: LogEvent.self).first)
        XCTAssertNil(log.attributes.internalAttributes?["application_id"])
        XCTAssertNil(log.attributes.internalAttributes?["session_id"])
        XCTAssertNil(log.attributes.internalAttributes?["view.id"])
        XCTAssertNil(log.attributes.internalAttributes?["user_action.id"])
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.target_scene_id"] as? String,
            sceneIdentifier
        )
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.context_captured"] as? Bool,
            true
        )
    }

    func testWhenPendingActionHasNoSceneSnapshot_itDoesNotAdoptRepresentativeAction() throws {
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )
        let representativeContext: RUMCoreContext = .mockWith(
            viewID: UUID().uuidString,
            userActionID: UUID().uuidString
        )
        featureScope.contextMock = .mockWith(additionalContext: [representativeContext])

        RUMContextHandoff.withValue(
            owner: RUMContextHandoff.owner(in: featureScope),
            rumContext: nil,
            sceneIdentifier: "scene-B",
            hasPendingUserAction: true
        ) {
            logger.error("message")
        }

        let log = try XCTUnwrap(featureScope.eventsWritten(ofType: LogEvent.self).first)
        XCTAssertNil(log.attributes.internalAttributes?["application_id"])
        XCTAssertNil(log.attributes.internalAttributes?["session_id"])
        XCTAssertNil(log.attributes.internalAttributes?["view.id"])
        XCTAssertNil(log.attributes.internalAttributes?["user_action.id"])
        let errorMessage = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMErrorMessage)
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_view_id"])
        XCTAssertNil(errorMessage.attributes["_dd.internal.rum.error.target_action_id"])
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.target_scene_id"] as? String,
            "scene-B"
        )
        XCTAssertEqual(
            errorMessage.attributes["_dd.internal.rum.error.context_captured"] as? Bool,
            true
        )
    }

    func testWhenRUMIntegrationIsEnabled_withRUMContext_butSampledOut_itDoesNotSendTelemetryError() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        let applicationID: String = .mockRandom()
        let sessionID: String = .mockRandom()

        // When
        featureScope.contextMock = .mockWith(
            additionalContext: [
                RUMCoreContext(
                    applicationID: applicationID,
                    sessionID: sessionID,
                    sessionSampler: .mockRejectAll()
                )
            ]
        )

        logger.info("message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.attributes.internalAttributes?["application_id"])
        XCTAssertNil(log.attributes.internalAttributes?["session_id"])
        XCTAssertNil(log.attributes.internalAttributes?["view.id"])
        XCTAssertNil(log.attributes.internalAttributes?["user_action.id"])
        XCTAssertTrue(featureScope.telemetryMock.messages.isEmpty)
    }

    func testWhenRUMIntegrationIsEnabled_withNoRUMContext_itDoesNotSendTelemetryError() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.info("message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.attributes.internalAttributes?["application_id"])
        XCTAssertNil(log.attributes.internalAttributes?["session_id"])
        XCTAssertNil(log.attributes.internalAttributes?["view.id"])
        XCTAssertNil(log.attributes.internalAttributes?["user_action.id"])
        XCTAssertTrue(featureScope.telemetryMock.messages.isEmpty)
    }

    // MARK: - Span Integration

    func testWhenActiveSpanIntegrationIsEnabled_itSendsLogWithSpanContext() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: true,
            backtraceReporter: BacktraceReporterMock()
        )

        let traceID: TraceID = .mock(.mockRandom(), .mockRandom())
        let spanID: SpanID = .mock(.mockRandom())

        // When
        featureScope.contextMock = .mockWith(
            additionalContext: [
                TraceCoreContext.Span(
                    traceID: traceID.toString(representation: .hexadecimal),
                    spanID: spanID.toString(representation: .decimal)
                )
            ]
        )
        logger.info("message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.internalAttributes?["dd.trace_id"] as? String, traceID.toString(representation: .hexadecimal))
        XCTAssertEqual(log.attributes.internalAttributes?["dd.span_id"] as? String, spanID.toString(representation: .decimal))
    }

    func testWhenActiveSpanIntegrationIsEnabled_withNoActiveSpan_itDoesNotSendTelemetryError() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: true,
            backtraceReporter: BacktraceReporterMock()
        )

        // When
        logger.info("message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.attributes.internalAttributes?["dd.trace_id"])
        XCTAssertNil(log.attributes.internalAttributes?["dd.span_id"])
        XCTAssertTrue(featureScope.telemetryMock.messages.isEmpty)
    }

    // MARK: - Attribute Encoding Error Handling

    /// These tests use `AnyEncodable` to wrap non-`Encodable` types, simulating real production scenarios.
    /// There are 2 possible use-cases:
    /// - **ObjC APIs** (primary production path): Customers use ObjC APIs like `addAttribute(forKey:value:)` which accepts `Any`.
    ///   SDK automatically wraps values in `AnyEncodable`, losing type safety. Telemetry shows this is the dominant error path.
    /// - **Swift APIs with manual wrapping**: Swift API requires `Encodable`, but customers can explicitly wrap non-encodable
    ///   types using `AnyEncodable(value)` to bypass compile-time checks.

    func testWhenMultipleAttributesFailToEncode_itReplacesAllMalformedAttributesWithNull() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let logger = RemoteLogger(
            featureScope: featureScope,
            globalAttributes: .mockAny(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false,
            backtraceReporter: BacktraceReporterMock()
        )

        // When - test various non-encodable types (closures are most common from telemetry)
        let closure1: (NSArray) -> Void = { _ in }
        let closure2: () -> Void = { }
        logger.addAttribute(forKey: "valid", value: "test")
        logger.addAttribute(forKey: "onComplete", value: AnyEncodable(closure1))
        logger.addAttribute(forKey: "callback", value: AnyEncodable(closure2))
        logger.addAttribute(forKey: "custom_object", value: AnyEncodable(NSObject()))
        logger.info("Test message")

        // Then - encode to trigger error handling
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)

        // Encode to JSON
        let jsonData = try JSONEncoder().dd.encodeWithAttributeRecovery(log)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Event sent with its valid attribute and malformed attributes replaced by null.
        XCTAssertEqual(jsonObject["valid"] as? String, "test")
        XCTAssertTrue(jsonObject["onComplete"] is NSNull)
        XCTAssertTrue(jsonObject["callback"] is NSNull)
        XCTAssertTrue(jsonObject["custom_object"] is NSNull)

        // And all errors logged
        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute") }.count,
            3
        )
    }
}
