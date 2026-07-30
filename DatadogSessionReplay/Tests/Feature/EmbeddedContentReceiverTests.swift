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
struct EmbeddedContentReceiverTests {
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
        let resourcesWriter = ResourceWriterMock()
        let receiver = EmbeddedContentReceiver(
            scope: scope,
            resourcesWriter: resourcesWriter,
            srContextPublisher: SRContextPublisher(core: NOPDatadogCore())
        )
        let message = EmbeddedContentMessage.records(
            .init(
                records: [
                    ["timestamp": 123, "type": 2],
                    ["slotId": "stale-slot-id", "type": 10]
                ],
                slotID: "native-slot-id",
                viewID: "embedded-view-id"
            )
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
        #expect(resourcesWriter.resources.isEmpty)
    }

    @available(iOS 13.0, *)
    @Test("Adds embedded records to the existing native record count")
    func embeddedRecordsContributeToExistingNativeRecordCount() {
        // Given
        let rumContext: RUMCoreContext = .mockWith(
            applicationID: "native-application-id"
        )
        let scope = FeatureScopeMock(
            context: .mockWith(additionalContext: [rumContext])
        )
        let resourcesWriter = ResourceWriterMock()
        let core = PassthroughCoreMock()
        let srContextPublisher = SRContextPublisher(core: core)
        srContextPublisher.incrementRecordCount(by: 3, forViewID: "shared-view-id")
        let receiver = EmbeddedContentReceiver(
            scope: scope,
            resourcesWriter: resourcesWriter,
            srContextPublisher: srContextPublisher
        )
        let message = EmbeddedContentMessage.records(
            .init(
                records: [
                    ["type": 2],
                    ["type": 10]
                ],
                slotID: "slot-id",
                viewID: "shared-view-id"
            )
        )

        // When
        _ = receiver.receive(message: .embeddedContent(message), from: core)

        // Then
        let recordsCountByViewID = core.context.additionalContext(
            ofType: SessionReplayCoreContext.RecordsCount.self
        )?.value
        #expect(recordsCountByViewID == ["shared-view-id": 5])
    }

    @available(iOS 13.0, *)
    @Test("Writes embedded resources using the native application ID")
    func writesEmbeddedResourcesUsingNativeApplicationID() throws {
        // Given
        let rumContext: RUMCoreContext = .mockWith(
            applicationID: "native-application-id"
        )
        let scope = FeatureScopeMock(
            context: .mockWith(additionalContext: [rumContext])
        )
        let resourcesWriter = ResourceWriterMock()
        let receiver = EmbeddedContentReceiver(
            scope: scope,
            resourcesWriter: resourcesWriter,
            srContextPublisher: SRContextPublisher(core: NOPDatadogCore())
        )
        let data = Data([0x01, 0x02, 0x03])
        let message = EmbeddedContentMessage.resource(
            .init(
                identifier: "resource-id",
                data: data,
                mimeType: "image/png"
            )
        )

        // When
        let result = receiver.receive(message: .embeddedContent(message), from: NOPDatadogCore())

        // Then
        let resourceBatch = try #require(resourcesWriter.resources.first)
        let resource = try #require(resourceBatch.first)
        #expect(result)
        #expect(scope.eventsWritten.isEmpty)
        #expect(resourcesWriter.resources.count == 1)
        #expect(resourceBatch.count == 1)
        #expect(resource.identifier == "resource-id")
        #expect(resource.data == data)
        #expect(resource.mimeType == "image/png")
        #expect(resource.context == .init(rumContext.applicationID))
    }

    @available(iOS 13.0, *)
    @Test("Drops embedded messages when RUM context is unavailable")
    func dropsEmbeddedMessagesWhenRUMContextIsUnavailable() {
        // Given
        let scope = FeatureScopeMock()
        let resourcesWriter = ResourceWriterMock()
        let receiver = EmbeddedContentReceiver(
            scope: scope,
            resourcesWriter: resourcesWriter,
            srContextPublisher: SRContextPublisher(core: NOPDatadogCore())
        )
        let message = EmbeddedContentMessage.records(
            .init(
                records: [["type": 2]],
                slotID: "slot-id",
                viewID: "view-id"
            )
        )

        // When
        let result = receiver.receive(message: .embeddedContent(message), from: NOPDatadogCore())

        // Then
        #expect(result)
        #expect(scope.eventsWritten.isEmpty)
        #expect(resourcesWriter.resources.isEmpty)
    }

    @available(iOS 13.0, *)
    @Test("Drops embedded messages when the native RUM session is not sampled")
    func dropsEmbeddedMessagesWhenNativeRUMSessionIsNotSampled() {
        // Given
        let rumContext: RUMCoreContext = .mockWith(sessionSampleRate: 0)
        let scope = FeatureScopeMock(
            context: .mockWith(additionalContext: [rumContext])
        )
        let resourcesWriter = ResourceWriterMock()
        let receiver = EmbeddedContentReceiver(
            scope: scope,
            resourcesWriter: resourcesWriter,
            srContextPublisher: SRContextPublisher(core: NOPDatadogCore())
        )
        let message = EmbeddedContentMessage.resource(
            .init(
                identifier: "resource-id",
                data: Data(),
                mimeType: "image/png"
            )
        )

        // When
        let result = receiver.receive(message: .embeddedContent(message), from: NOPDatadogCore())

        // Then
        #expect(result)
        #expect(scope.eventsWritten.isEmpty)
        #expect(resourcesWriter.resources.isEmpty)
    }

    @available(iOS 13.0, *)
    @Test("Rejects messages for other receivers")
    func rejectsMessagesForOtherReceivers() {
        // Given
        let scope = FeatureScopeMock()
        let resourcesWriter = ResourceWriterMock()
        let receiver = EmbeddedContentReceiver(
            scope: scope,
            resourcesWriter: resourcesWriter,
            srContextPublisher: SRContextPublisher(core: NOPDatadogCore())
        )

        // When
        let result = receiver.receive(message: .payload("value"), from: NOPDatadogCore())

        // Then
        #expect(!result)
        #expect(scope.eventsWritten.isEmpty)
        #expect(resourcesWriter.resources.isEmpty)
    }
}
#endif
