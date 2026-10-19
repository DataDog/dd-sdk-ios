/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import Testing
import DatadogInternal
import TestUtilities

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct ResourceRequestBuilderReconciliationTests {
    private let availabilityStore: ResourceAvailabilityStore
    private let builder: ResourceRequestBuilder
    private let events = ["first", "second"].map { identifier in
        let resource: EnrichedResource = .mockWith(identifier: identifier, context: .init("application"))
        return Event(data: try! JSONEncoder().encode(resource), metadata: Data(identifier.utf8))
    }

    init() {
        let scope = FeatureScopeMock()
        let availabilityStore = ResourceAvailabilityStore(scope: scope)
        self.availabilityStore = availabilityStore
        self.builder = ResourceRequestBuilder(
            customUploadURL: nil,
            availabilityStore: availabilityStore,
            telemetry: scope.telemetry
        )
    }

    @Test("Skips reconciliation when resources still need uploading", arguments: [Set<String>(), ["first"]])
    func skipsReconciliationWhenResourcesStillNeedUploading(confirmedIdentifiers: Set<String>) throws {
        // Given
        availabilityStore.insert(["first", "second"], forApplicationID: "other-application")
        availabilityStore.insert(confirmedIdentifiers, forApplicationID: "application")

        // When
        let reconciliation = try builder.reconciliation(for: events, with: .mockAny(), execution: .mockAny())

        // Then
        guard case .skip = reconciliation else {
            Issue.record("Expected direct uploads while the reconciliation endpoint is unavailable")
            return
        }
        #expect(!availabilityStore.contains("second", forApplicationID: "application"))
    }

    @Test("Resolves batches already confirmed for their application")
    func resolvesBatchesAlreadyConfirmedForTheirApplication() throws {
        // Given
        availabilityStore.insert(["first", "second"], forApplicationID: "application")

        // When
        let reconciliation = try builder.reconciliation(for: events, with: .mockAny(), execution: .mockAny())

        // Then
        guard case .resolved = reconciliation else {
            Issue.record("Expected confirmed resources to complete without a request")
            return
        }
    }

    @Test(
        "Decodes confirmations and preserves remaining events and metadata",
        arguments: [
            (body: #"{"stored_resource_ids":[]}"#, remainingIndices: [0, 1]),
            (body: #"{"stored_resource_ids":["first"]}"#, remainingIndices: [1]),
            (body: #"{"stored_resource_ids":["first","second"]}"#, remainingIndices: [])
        ]
    )
    func decodesConfirmationsAndPreservesRemainingEventsAndMetadata(body: String, remainingIndices: [Int]) throws {
        // When
        let remaining = try builder.reconcile(
            from: events,
            using: .mockResponseWith(statusCode: 200),
            data: Data(body.utf8)
        )

        // Then
        #expect(remaining == remainingIndices.map { events[$0] })
        for (index, identifier) in ["first", "second"].enumerated() {
            #expect(availabilityStore.contains(identifier, forApplicationID: "application") == !remainingIndices.contains(index))
        }
        #expect(!availabilityStore.contains("first", forApplicationID: "other-application"))
    }

    @Test("Keeps resources omitted from the latest response eligible for retry")
    func keepsResourcesOmittedFromTheLatestResponseEligibleForRetry() throws {
        // Given
        availabilityStore.insert(["first"], forApplicationID: "application")
        let body = #"{"stored_resource_ids":["second"]}"#

        // When
        let remaining = try builder.reconcile(
            from: events,
            using: .mockResponseWith(statusCode: 200),
            data: Data(body.utf8)
        )
        let retry = try builder.reconciliation(
            for: events,
            with: .mockAny(),
            execution: .init(previousResponseCode: 503, attempt: 1)
        )

        // Then
        #expect(remaining == [events[0]])
        #expect(!availabilityStore.contains("first", forApplicationID: "application"))
        #expect(availabilityStore.contains("second", forApplicationID: "application"))
        guard case .skip = retry else {
            Issue.record("Expected unconfirmed resources to remain eligible for upload on retry")
            return
        }
    }

    @Test(
        "Rejects missing or malformed response bodies",
        arguments: [nil, Data("{}".utf8)] as [Data?]
    )
    func rejectsMissingOrMalformedResponseBodies(data: Data?) {
        // When, Then
        #expect(throws: (any Error).self) {
            try builder.reconcile(from: events, using: .mockResponseWith(statusCode: 200), data: data)
        }
    }

    @Test("Rejects malformed batches before caching confirmations")
    func rejectsMalformedBatchesBeforeCachingConfirmations() {
        // Given
        let malformedEvents = events + [Event(data: Data("invalid".utf8))]

        // When, Then
        #expect(throws: DecodingError.self) {
            try builder.reconcile(
                from: malformedEvents,
                using: .mockResponseWith(statusCode: 200),
                data: Data(#"{"stored_resource_ids":["first"]}"#.utf8)
            )
        }
        #expect(!availabilityStore.contains("first", forApplicationID: "application"))
    }
}
#endif
