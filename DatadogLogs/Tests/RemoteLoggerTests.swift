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

private final class RetainedLogCaptureScope: FeatureScope, RUMContextHandoffEventWriting, @unchecked Sendable {
    let base: FeatureScopeMock
    let capture: RUMContextHandoff.Capture?
    private(set) var captureWrites = 0

    init(base: FeatureScopeMock, capture: RUMContextHandoff.Capture?) {
        self.base = base
        self.capture = capture
    }

    func eventWriteContextWithRUMCapture(
        bypassConsent: Bool,
        _ block: @escaping (DatadogContext, Writer, RUMContextHandoff.Capture?) -> Void
    ) {
        captureWrites += 1
        let retained = capture
        base.eventWriteContext(bypassConsent: bypassConsent) { context, writer in
            block(context, writer, retained)
        }
    }

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        base.eventWriteContext(bypassConsent: bypassConsent, block)
    }
    func context(_ block: @escaping (DatadogContext) -> Void) { base.context(block) }
    var dataStore: DataStore { base.dataStore }
    var telemetry: Telemetry { base.telemetry }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func set(anonymousId: String?) { base.set(anonymousId: anonymousId) }
}

final class CapturedLogOutputTests: XCTestCase {
    private func logger(
        scope: FeatureScope,
        configuration: RemoteLogger.Configuration = .mockWith(),
        rumContextIntegration: Bool = true
    ) -> RemoteLogger {
        RemoteLogger(
            featureScope: scope,
            globalAttributes: .mockAny(),
            configuration: configuration,
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: rumContextIntegration,
            activeSpanIntegration: true,
            backtraceReporter: BacktraceReporterMock()
        )
    }

    private func capture(owner: RUMContextHandoff.Owner, context: RUMCoreContext?) -> RUMContextHandoff.Capture {
        .init(owner: owner, value: .init(
            rumContext: context, sceneIdentifier: "original-scene", hasPendingUserAction: false, excludedUserActionID: nil
        ))
    }

    private func serialized(_ base: FeatureScopeMock) throws -> [String: Any] {
        let logs = base.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        let data = try JSONEncoder().dd.encodeWithAttributeRecovery(log)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDeferredCapturedLogAndMirrorKeepOriginalAcceptedActionAndDeliveryTrace() throws {
        let original = RUMCoreContext.mockWith(
            applicationID: "original-application", sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, viewID: "original-view", userActionID: "prior-action"
        )
        let delivery = RUMCoreContext.mockWith(
            applicationID: "delivery-application", sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, viewID: "delivery-view", userActionID: "later-action"
        )
        let owner = RUMContextHandoff.Owner()
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: original)
        let retained = RUMContextHandoff.Capture(owner: owner, value: .init(
            rumContext: original,
            sceneIdentifier: "original-scene",
            hasPendingUserAction: true,
            excludedUserActionID: original.userActionID,
            actionReceipt: receipt
        ))
        let base = FeatureScopeMock(context: .mockWith(additionalContext: [original]), deferEventWriteContext: true)
        let scope = RetainedLogCaptureScope(base: base, capture: retained)
        let logger = logger(scope: scope)
        var completions = 0
        logger.internalLog(level: .error, message: "captured-error", error: nil, attributes: ["retained": "value"]) {
            completions += 1
        }
        XCTAssertTrue(base.eventsWritten.isEmpty)
        receipt.accept(sessionID: original.sessionID, viewID: "original-view", actionID: "accepted-action")
        base.contextMock = .mockWith(additionalContext: [delivery, TraceCoreContext.Span(traceID: "delivery-trace", spanID: "delivery-span")])
        base.flushDeferredEventWriteContexts()
        let json = try serialized(base)
        XCTAssertEqual(json["application_id"] as? String, "original-application")
        XCTAssertEqual(json["session_id"] as? String, original.sessionID)
        XCTAssertEqual(json["view.id"] as? String, "original-view")
        XCTAssertEqual(json["user_action.id"] as? String, "accepted-action")
        XCTAssertEqual(json["dd.trace_id"] as? String, "delivery-trace")
        XCTAssertEqual(json["dd.span_id"] as? String, "delivery-span")
        XCTAssertEqual(json["retained"] as? String, "value")
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(scope.captureWrites, 1)
        XCTAssertEqual(base.messagesSent().count, 1)
        let mirror = try XCTUnwrap(base.messagesSent().firstPayload as? RUMCapturedErrorMessage)
        XCTAssertTrue(mirror.capture.owner === owner)
        XCTAssertTrue(mirror.capture.value.actionReceipt === receipt)
        XCTAssertEqual(mirror.capture.value.resolvedRUMContext(for: owner)?.viewID, "original-view")
        XCTAssertEqual(mirror.capture.value.resolvedRUMContext(for: owner)?.userActionID, "accepted-action")
        XCTAssertEqual(mirror.error.message, "captured-error")
    }

    func testAuthoritativeNilAndInvalidatedCapturedOwnerCannotUseDeliveryRUMTags() throws {
        for invalidated in [false, true] {
            let owner = RUMContextHandoff.Owner()
            let original = invalidated ? RUMCoreContext.mockWith(viewID: "original-view") : nil
            let base = FeatureScopeMock(deferEventWriteContext: true)
            let scope = RetainedLogCaptureScope(base: base, capture: capture(owner: owner, context: original))
            let logger = logger(scope: scope)
            logger.error("retained-error")
            if invalidated { owner.invalidate() }
            base.contextMock = .mockWith(additionalContext: [RUMCoreContext.mockWith(viewID: "delivery-view", userActionID: "later-action")])
            base.flushDeferredEventWriteContexts()
            let json = try serialized(base)
            for key in ["application_id", "session_id", "view.id", "user_action.id"] { XCTAssertNil(json[key]) }
            let mirror = try XCTUnwrap(base.messagesSent().firstPayload as? RUMCapturedErrorMessage)
            XCTAssertTrue(mirror.capture.owner === owner)
            XCTAssertNil(mirror.capture.value.resolvedRUMContext(for: owner))
            XCTAssertEqual(scope.captureWrites, 1)
        }
    }

    func testCapturedMirrorKeepsOwnershipWhenLogRUMTagsAreDisabledAndMapperChangesMessage() throws {
        let owner = RUMContextHandoff.Owner()
        let original = RUMCoreContext.mockWith(viewID: "original-view")
        let base = FeatureScopeMock(deferEventWriteContext: true)
        let scope = RetainedLogCaptureScope(base: base, capture: capture(owner: owner, context: original))
        let mapper = SyncLogEventMapper { log in
            var mapped = log
            mapped.message = "mapped-error"
            return mapped
        }
        let logger = logger(scope: scope, configuration: .mockWith(eventMapper: mapper), rumContextIntegration: false)
        logger.error("original-error", attributes: [Logs.Attributes.errorFingerprint: "retained-fingerprint"])
        base.contextMock = .mockWith(additionalContext: [RUMCoreContext.mockWith(viewID: "delivery-view")])
        base.flushDeferredEventWriteContexts()
        let json = try serialized(base)
        XCTAssertEqual(json["message"] as? String, "mapped-error")
        XCTAssertNil(json["view.id"])
        let mirror = try XCTUnwrap(base.messagesSent().firstPayload as? RUMCapturedErrorMessage)
        XCTAssertEqual(mirror.error.message, "mapped-error")
        XCTAssertEqual(mirror.error.attributes[Logs.Attributes.errorFingerprint] as? String, "retained-fingerprint")
        XCTAssertEqual(mirror.capture.value.resolvedRUMContext(for: owner)?.viewID, "original-view")
    }

    func testCapturedSamplingThresholdAndMapperDropsDoNotProduceLogMirrorOrCompletion() throws {
        for configuration in [
            RemoteLogger.Configuration.mockWith(sampler: .mockRejectAll()),
            .mockWith(threshold: .critical),
            .mockWith(eventMapper: SyncLogEventMapper { _ in nil })
        ] {
            let owner = RUMContextHandoff.Owner()
            let base = FeatureScopeMock(deferEventWriteContext: true)
            let scope = RetainedLogCaptureScope(base: base, capture: capture(owner: owner, context: .mockWith(viewID: "original-view")))
            let logger = logger(scope: scope, configuration: configuration)
            var completions = 0
            logger.internalLog(level: .error, message: "dropped-error", error: nil, attributes: nil) { completions += 1 }
            base.flushDeferredEventWriteContexts()
            XCTAssertTrue(base.eventsWritten.isEmpty)
            XCTAssertTrue(base.messagesSent().isEmpty)
            XCTAssertEqual(completions, 0)
        }
    }

    func testCustomScopeAndUncapturedBuiltinCapabilityKeepLegacyMirrorAndDeliveryTags() throws {
        for builtinCapability in [false, true] {
            let base = FeatureScopeMock(deferEventWriteContext: true)
            let scope: FeatureScope = builtinCapability ? RetainedLogCaptureScope(base: base, capture: nil) : base
            let logger = logger(scope: scope)
            var completions = 0
            logger.internalLog(level: .error, message: "legacy-error", error: nil, attributes: nil) { completions += 1 }
            base.contextMock = .mockWith(additionalContext: [RUMCoreContext.mockWith(viewID: "delivery-view")])
            base.flushDeferredEventWriteContexts()
            let json = try serialized(base)
            XCTAssertEqual(json["view.id"] as? String, "delivery-view")
            XCTAssertEqual(base.messagesSent().count, 1)
            XCTAssertNotNil(base.messagesSent().firstPayload as? RUMErrorMessage)
            XCTAssertNil(base.messagesSent().firstPayload as? RUMCapturedErrorMessage)
            XCTAssertEqual(completions, 1)
        }
        let nop = logger(scope: NOPFeatureScope())
        var nopCompletions = 0
        nop.internalLog(level: .error, message: "nop-error", error: nil, attributes: nil) { nopCompletions += 1 }
        XCTAssertEqual(nopCompletions, 0)
    }

    func testDeferredCapturedLoggerCanDeallocateWithoutWritingOrCompleting() throws {
        let owner = RUMContextHandoff.Owner()
        let base = FeatureScopeMock(deferEventWriteContext: true)
        let scope = RetainedLogCaptureScope(base: base, capture: capture(owner: owner, context: .mockWith(viewID: "original-view")))
        var retainedLogger: RemoteLogger? = logger(scope: scope)
        weak var weakLogger = retainedLogger
        var completions = 0
        retainedLogger?.internalLog(level: .error, message: "released-error", error: nil, attributes: nil) { completions += 1 }
        retainedLogger = nil
        XCTAssertNil(weakLogger)
        base.flushDeferredEventWriteContexts()
        XCTAssertTrue(base.eventsWritten.isEmpty)
        XCTAssertTrue(base.messagesSent().isEmpty)
        XCTAssertEqual(completions, 0)
    }
}
