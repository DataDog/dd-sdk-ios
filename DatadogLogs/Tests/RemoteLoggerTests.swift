/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
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
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
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
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        logger.error("Error message")

        // Then
        let errorBaggage = try XCTUnwrap(featureScope.messagesSent().firstBaggage(withKey: "error"))
        let error: ExpectedErrorMessage = try errorBaggage.decode()
        XCTAssertEqual(error.message, "Error message")
    }

    func testWhenCrossPlatformCrashErrorLogged_itDoesNotPostToMessageBus() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        logger.error("Error message", error: nil, attributes: [CrossPlatformAttributes.errorLogIsCrash: true])

        // Then
        XCTAssertEqual(featureScope.messagesSent().count, 0)
    }

    func testWhenAttributesContainIncludeBinaryImages_itPostsBinaryImagesToMessageBus() throws {
        let stubBacktrace: BacktraceReport = .mockRandom()
        let logsFeature = LogsFeature.mockWith(
            backtraceReporter: BacktraceReporterMock(backtrace: stubBacktrace)
        )
        let core = SingleFeatureCoreMock(feature: logsFeature)
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: core,
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        logger.error("Information message", error: ErrorMock(), attributes: [CrossPlatformAttributes.includeBinaryImages: true])

        // Then
        let errorBaggage = try XCTUnwrap(featureScope.messagesSent().firstBaggage(withKey: "error"))
        let error: ExpectedErrorMessage = try errorBaggage.decode()
        // This is removed because binary images are sent in the message, so the additional attribute isn't needed
        XCTAssertNil(error.attributes[CrossPlatformAttributes.includeBinaryImages])
        XCTAssertEqual(error.binaryImages?.count, stubBacktrace.binaryImages.count)
        for i in 0..<stubBacktrace.binaryImages.count {
            let logBacktrace = error.binaryImages![i]
            let errorBacktrace = stubBacktrace.binaryImages[i]
            XCTAssertEqual(logBacktrace.libraryName, errorBacktrace.libraryName)
            XCTAssertEqual(logBacktrace.uuid, errorBacktrace.uuid)
            XCTAssertEqual(logBacktrace.architecture, errorBacktrace.architecture)
            XCTAssertEqual(logBacktrace.isSystemLibrary, errorBacktrace.isSystemLibrary)
            XCTAssertEqual(logBacktrace.loadAddress, errorBacktrace.loadAddress)
            XCTAssertEqual(logBacktrace.maxAddress, errorBacktrace.maxAddress)
        }
    }

    func testWhenErrorLogged_itPostsToMessageBus_withOtherCrossPlatformAttributesIntact() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
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
        let errorBaggage = try XCTUnwrap(featureScope.messagesSent().firstBaggage(withKey: "error"))
        let error: ExpectedErrorMessage = try errorBaggage.decode()
        XCTAssertEqual(error.attributes[CrossPlatformAttributes.errorSourceType]?.value as? String, "flutter")
        XCTAssertEqual(error.attributes[Logs.Attributes.errorFingerprint]?.value as? String, mockFingerprint)
    }

    func testWhenErrorLoggedFromInternal_itPostsToMessageBus_withSourceTypeInjected() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
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
        let errorBaggage = try XCTUnwrap(featureScope.messagesSent().firstBaggage(withKey: "error"))
        let error: ExpectedErrorMessage = try errorBaggage.decode()
        XCTAssertEqual(error.attributes[CrossPlatformAttributes.errorSourceType]?.value as? String, "flutter")
        XCTAssertEqual(error.attributes[Logs.Attributes.errorFingerprint]?.value as? String, mockFingerprint)
    }

    // MARK: - Attributes

    func testWhenFeatureHasAttributes_itSendsAttributesOnLog() throws {
        // Given
        let logsFeature = LogsFeature.mockAny()
        let core = SingleFeatureCoreMock(feature: logsFeature)
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: core,
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        let attributeKey = String.mockRandom()
        let attributeValue = String.mockRandom()
        logsFeature.addAttribute(forKey: attributeKey, value: attributeValue)

        logger.info("Information message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.userAttributes[attributeKey] as? String, attributeValue)
    }

    func testWhenFeatureHasAttributes_andLoggerHasAttributes_itSendsLoggerAttributesOnLog() throws {
        // Given
        let logsFeature = LogsFeature.mockAny()
        let core = SingleFeatureCoreMock(feature: logsFeature)
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: core,
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        let attributeKey = String.mockRandom()
        let featureAttributeValue = String.mockRandom()
        let loggerAttributeValue = String.mockRandom()
        logsFeature.addAttribute(forKey: attributeKey, value: featureAttributeValue)
        logger.addAttribute(forKey: attributeKey, value: loggerAttributeValue)

        logger.info("Information message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.userAttributes[attributeKey] as? String, loggerAttributeValue)
    }

    func testWhenFeatureHasAttributes_andLogCallHasAttributes_itSendsLogCallAttributesOnLog() throws {
        // Given
        let logsFeature = LogsFeature.mockAny()
        let core = SingleFeatureCoreMock(feature: logsFeature)
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: core,
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        let attributeKey = String.mockRandom()
        let featureAttributeValue = String.mockRandom()
        logsFeature.addAttribute(forKey: attributeKey, value: featureAttributeValue)

        let logCallValue = String.mockRandom()
        logger.info("Information message", attributes: [attributeKey: logCallValue])

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.attributes.userAttributes[attributeKey] as? String, logCallValue)
    }

    func testItSendsGlobalAttributesErrorAlongWithErrorLog() throws {
        // Given
        let logsFeature = LogsFeature.mockAny()
        let core = SingleFeatureCoreMock(feature: logsFeature)
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: core,
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        let attributeKey = String.mockRandom()
        let attributeValue = String.mockRandom()
        logsFeature.addAttribute(forKey: attributeKey, value: attributeValue)

        // When
        logger.error("Error message")

        // Then
        let errorBaggage = try XCTUnwrap(featureScope.messagesSent().firstBaggage(withKey: "error"))
        let error: ExpectedErrorMessage = try errorBaggage.decode()
        XCTAssertEqual(error.attributes[attributeKey]?.value as? String, attributeValue)
    }

    func testWhenAttributesContainErrorFingerprint_itAddsItToTheLogEvent() throws {
        // Given
        let logsFeature = LogsFeature.mockAny()
        let core = SingleFeatureCoreMock(feature: logsFeature)
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: core,
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
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
        let logsFeature = LogsFeature.mockWith(
            backtraceReporter: BacktraceReporterMock(backtrace: stubBacktrace)
        )
        let core = SingleFeatureCoreMock(feature: logsFeature)
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: core,
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: false
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

    // MARK: - RUM Integration

    func testWhenRUMIntegrationIsEnabled_itSendsLogWithRUMContext() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false
        )

        let applicationID: String = .mockRandom()
        let sessionID: String = .mockRandom()
        let viewID: String = .mockRandom()
        let actionID: String = .mockRandom()

        // When
        featureScope.contextMock = .mockWith(
            baggages: [
                "rum" : .init([
                    "application.id": applicationID,
                    "session.id": sessionID,
                    "view.id": viewID,
                    "user_action.id": actionID
                ])
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

    func testWhenRUMIntegrationIsEnabled_withNoRUMContext_itDoesNotSendTelemetryError() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false
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

    func testWhenRUMIntegrationIsEnabled_withMalformedRUMContext_itSendsTelemetryError() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: true,
            activeSpanIntegration: false
        )

        // When
        featureScope.contextMock = .mockWith(
            baggages: [
                "rum" : .init("malformed RUM context")
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

        let error = try XCTUnwrap(featureScope.telemetryMock.messages.firstError())
        XCTAssert(error.message.contains("Fails to decode RUM context from Logs - typeMismatch"))
    }

    // MARK: - Span Integration

    func testWhenActiveSpanIntegrationIsEnabled_itSendsLogWithSpanContext() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: true
        )

        let traceID: TraceID = .mock(.mockRandom(), .mockRandom())
        let spanID: SpanID = .mock(.mockRandom())

        // When
        featureScope.contextMock = .mockWith(
            baggages: [
                "span_context" : .init([
                    "dd.trace_id": traceID.toString(representation: .hexadecimal),
                    "dd.span_id": spanID.toString(representation: .decimal)
                ])
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
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: true
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

    func testWhenActiveSpanIntegrationIsEnabled_withMalformedRUMContext_itSendsTelemetryError() throws {
        // Given
        let logger = RemoteLogger(
            featureScope: featureScope,
            core: NOPDatadogCore(),
            configuration: .mockAny(),
            dateProvider: RelativeDateProvider(),
            rumContextIntegration: false,
            activeSpanIntegration: true
        )

        // When
        featureScope.contextMock = .mockWith(
            baggages: [
                "span_context" : .init("malformed Span context")
            ]
        )
        logger.info("message")

        // Then
        let logs = featureScope.eventsWritten(ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertNil(log.attributes.internalAttributes?["dd.trace_id"])
        XCTAssertNil(log.attributes.internalAttributes?["dd.span_id"])

        let error = try XCTUnwrap(featureScope.telemetryMock.messages.firstError())
        XCTAssert(error.message.contains("Fails to decode Span context from Logs - typeMismatch"))
    }
}
