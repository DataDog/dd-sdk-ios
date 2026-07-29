/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import Testing
import TestUtilities

@testable import DatadogInternal
@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct EmbeddedContentRecordReceiverTests {
    @available(iOS 13.0, *)
    @Test("Writes embedded records using native session context and embedded view ID")
    func writesEmbeddedRecordsUsingNativeSessionContextAndEmbeddedViewID() throws {
        // Given
        let rumContext: RUMCoreContext = .mockWith(
            applicationID: "native-application-id"
        )
        let scope = FeatureScopeMock(
            context: .mockWith(additionalContext: [rumContext])
        )
        let receiver = EmbeddedContentRecordReceiver(scope: scope)
        let message = EmbeddedContentMessage(
            records: [
                ["timestamp": 123, "type": 2],
                ["slotId": "stale-slot-id", "type": 10]
            ],
            slotID: "native-slot-id",
            viewID: "embedded-view-id"
        )

        // When
        let result = receiver.receive(message: .embeddedContent(message), from: NOPDatadogCore())

        // Then
        let expectedSegment: [String: Any] = [
            "applicationID": rumContext.applicationID,
            "sessionID": rumContext.sessionID,
            "viewID": "embedded-view-id",
            "records": [
                ["timestamp": 123, "type": 2, "slotId": "native-slot-id"],
                ["slotId": "native-slot-id", "type": 10]
            ]
        ]
        let actualSegment = try #require(scope.eventsWritten.first)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(result)
        #expect(scope.eventsWritten.count == 1)
        #expect(
            try encoder.encode(AnyCodable(actualSegment))
                == encoder.encode(AnyCodable(expectedSegment))
        )
    }

    @available(iOS 13.0, *)
    @Test("Drops embedded records when RUM context is unavailable")
    func dropsEmbeddedRecordsWhenRUMContextIsUnavailable() {
        // Given
        let scope = FeatureScopeMock()
        let receiver = EmbeddedContentRecordReceiver(scope: scope)
        let message = EmbeddedContentMessage(
            records: [["type": 2]],
            slotID: "slot-id",
            viewID: "view-id"
        )

        // When
        let result = receiver.receive(message: .embeddedContent(message), from: NOPDatadogCore())

        // Then
        #expect(result)
        #expect(scope.eventsWritten.isEmpty)
    }

    @available(iOS 13.0, *)
    @Test("Drops embedded records when the native RUM session is not sampled")
    func dropsEmbeddedRecordsWhenNativeRUMSessionIsNotSampled() {
        // Given
        let rumContext: RUMCoreContext = .mockWith(sessionSampleRate: 0)
        let scope = FeatureScopeMock(
            context: .mockWith(additionalContext: [rumContext])
        )
        let receiver = EmbeddedContentRecordReceiver(scope: scope)
        let message = EmbeddedContentMessage(
            records: [["type": 2]],
            slotID: "slot-id",
            viewID: "view-id"
        )

        // When
        let result = receiver.receive(message: .embeddedContent(message), from: NOPDatadogCore())

        // Then
        #expect(result)
        #expect(scope.eventsWritten.isEmpty)
    }

    @available(iOS 13.0, *)
    @Test("Rejects messages for other receivers")
    func rejectsMessagesForOtherReceivers() {
        // Given
        let scope = FeatureScopeMock()
        let receiver = EmbeddedContentRecordReceiver(scope: scope)

        // When
        let result = receiver.receive(message: .payload("value"), from: NOPDatadogCore())

        // Then
        #expect(!result)
        #expect(scope.eventsWritten.isEmpty)
    }
}
#endif
