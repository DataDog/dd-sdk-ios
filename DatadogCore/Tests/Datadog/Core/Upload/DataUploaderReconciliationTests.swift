/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Testing
import DatadogInternal
import TestUtilities

@testable import DatadogCore

@Suite(.datadogTesting)
struct DataUploaderReconciliationTests {
    private let events = [
        Event(data: "first".utf8Data, metadata: "first metadata".utf8Data),
        Event(data: "second".utf8Data, metadata: "second metadata".utf8Data)
    ]
    private let reconciliationRequest: URLRequest = .mockAny()
    private let uploadRequest: URLRequest = .mockWith(httpMethod: "POST")

    @Test("Uploads original events when reconciliation is skipped")
    func uploadsOriginalEventsWhenReconciliationIsSkipped() throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        var uploadedEvents: [[Event]] = []
        builder.requestStub = { events, _, _ in
            uploadedEvents.append(events)
            return uploadRequest
        }
        builder.reconciliationStub = { _, _, _ in .skip }
        let (uploader, client) = makeUploader(builder: builder)

        // When
        let status = try uploader.upload(events: events, context: .mockAny(), previous: nil)

        // Then
        #expect(client.requestsSent() == [uploadRequest])
        #expect(uploadedEvents == [events])
        #expect(status.responseCode == 202)
    }

    @Test("Completes without requests when the batch is already resolved")
    func completesWithoutRequestsWhenTheBatchIsAlreadyResolved() throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        builder.reconciliationStub = { _, _, _ in .resolved }
        let (uploader, client) = makeUploader(builder: builder)

        // When
        let status = try uploader.upload(events: events, context: .mockAny(), previous: .mockWith(attempt: 2))

        // Then
        #expect(client.requestsSent().isEmpty)
        #expect(!status.needsRetry)
        #expect(status.responseCode == nil)
        #expect(status.error == nil)
        #expect(status.attempt == 3)
    }

    @Test("Uploads remaining events with their metadata when some events are confirmed")
    func uploadsRemainingEventsWithTheirMetadataWhenSomeEventsAreConfirmed() throws {
        // Given
        let context: DatadogContext = .mockRandom()
        let body: Data = .mockAny()
        let builder = FeatureEventReconcilerMock()
        var uploadedEvents: [[Event]] = []
        builder.reconciliationStub = { receivedEvents, receivedContext, _ in
            #expect(receivedEvents == events)
            #expect(receivedContext.site == context.site)
            #expect(receivedContext.clientToken == context.clientToken)
            #expect(receivedContext.ddTags == context.ddTags)
            return .request(reconciliationRequest)
        }
        builder.reconcileStub = { receivedEvents, response, data in
            #expect(receivedEvents == events)
            #expect(response.statusCode == 200)
            #expect(data == body)
            return [events[1]]
        }
        builder.requestStub = { events, _, _ in
            uploadedEvents.append(events)
            return uploadRequest
        }
        let (uploader, client) = makeUploader(builder: builder, body: body)

        // When
        let status = try uploader.upload(events: events, context: context, previous: nil)

        // Then
        #expect(client.requestsSent() == [reconciliationRequest, uploadRequest])
        #expect(uploadedEvents == [[events[1]]])
        #expect(status.responseCode == 202)
        #expect(!status.needsRetry)
    }

    @Test("Completes without uploading when all events are confirmed")
    func completesWithoutUploadingWhenAllEventsAreConfirmed() throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        builder.reconciliationStub = { _, _, _ in .request(reconciliationRequest) }
        builder.reconcileStub = { _, _, _ in [] }
        let (uploader, client) = makeUploader(builder: builder)

        // When
        let status = try uploader.upload(events: events, context: .mockAny(), previous: nil)

        // Then
        #expect(client.requestsSent() == [reconciliationRequest])
        #expect(!status.needsRetry)
        #expect(status.responseCode == nil)
        #expect(status.error == nil)
    }

    @Test("Uploads original events when the reconciliation request cannot be built")
    func uploadsOriginalEventsWhenTheReconciliationRequestCannotBeBuilt() throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        var uploadedEvents: [[Event]] = []
        builder.requestStub = { events, _, _ in
            uploadedEvents.append(events)
            return uploadRequest
        }
        builder.reconciliationStub = { _, _, _ in throw ErrorMock() }
        let (uploader, client) = makeUploader(builder: builder)

        // When
        let status = try uploader.upload(events: events, context: .mockAny(), previous: nil)

        // Then
        #expect(client.requestsSent() == [uploadRequest])
        #expect(uploadedEvents == [events])
        #expect(status.responseCode == 202)
    }

    @Test("Uploads original events when reconciliation has a network error")
    func uploadsOriginalEventsWhenReconciliationHasANetworkError() throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        var uploadedEvents: [[Event]] = []
        builder.requestStub = { events, _, _ in
            uploadedEvents.append(events)
            return uploadRequest
        }
        builder.reconciliationStub = { _, _, _ in .request(reconciliationRequest) }
        let (uploader, client) = makeUploader(builder: builder, reconciliationError: URLError(.timedOut))

        // When
        let status = try uploader.upload(events: events, context: .mockAny(), previous: nil)

        // Then
        #expect(client.requestsSent() == [reconciliationRequest, uploadRequest])
        #expect(uploadedEvents == [events])
        #expect(status.responseCode == 202)
        #expect(status.error == nil)
    }

    @Test(
        "Uploads original events without reconciling unsuccessful responses",
        arguments: [199, 300]
    )
    func uploadsOriginalEventsWithoutReconcilingUnsuccessfulResponses(code: Int) throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        var uploadedEvents: [[Event]] = []
        builder.requestStub = { events, _, _ in
            uploadedEvents.append(events)
            return uploadRequest
        }
        builder.reconciliationStub = { _, _, _ in .request(reconciliationRequest) }
        var reconcileCount = 0
        builder.reconcileStub = { _, _, _ in
            reconcileCount += 1
            return []
        }
        let (uploader, client) = makeUploader(builder: builder, reconciliationCode: code)

        // When
        let status = try uploader.upload(events: events, context: .mockAny(), previous: nil)

        // Then
        #expect(client.requestsSent() == [reconciliationRequest, uploadRequest])
        #expect(uploadedEvents == [events])
        #expect(reconcileCount == 0)
        #expect(status.responseCode == 202)
        #expect(!status.needsRetry)
    }

    @Test("Uploads original events when the feature cannot reconcile the response")
    func uploadsOriginalEventsWhenTheFeatureCannotReconcileTheResponse() throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        var uploadedEvents: [[Event]] = []
        builder.requestStub = { events, _, _ in
            uploadedEvents.append(events)
            return uploadRequest
        }
        builder.reconciliationStub = { _, _, _ in .request(reconciliationRequest) }
        var reconcileCount = 0
        builder.reconcileStub = { _, _, _ in
            reconcileCount += 1
            throw ErrorMock()
        }
        let (uploader, client) = makeUploader(builder: builder)

        // When
        _ = try uploader.upload(events: events, context: .mockAny(), previous: nil)

        // Then
        #expect(client.requestsSent() == [reconciliationRequest, uploadRequest])
        #expect(uploadedEvents == [events])
        #expect(reconcileCount == 1)
    }

    @Test("Reconciles the original batch again when the upload needs retrying")
    func reconcilesTheOriginalBatchAgainWhenTheUploadNeedsRetrying() throws {
        // Given
        let builder = FeatureEventReconcilerMock()
        var reconciliationEvents: [[Event]] = []
        var reconciliationExecutions: [ExecutionContext] = []
        var uploadedEvents: [[Event]] = []
        var uploadExecutions: [ExecutionContext] = []
        builder.reconciliationStub = { events, _, execution in
            reconciliationEvents.append(events)
            reconciliationExecutions.append(execution)
            return .request(reconciliationRequest)
        }
        builder.reconcileStub = { _, _, _ in [events[1]] }
        builder.requestStub = { events, _, execution in
            uploadedEvents.append(events)
            uploadExecutions.append(execution)
            return uploadRequest
        }
        let (uploader, client) = makeUploader(builder: builder, uploadCode: 503)

        // When
        let first = try uploader.upload(events: events, context: .mockAny(), previous: nil)
        let second = try uploader.upload(events: events, context: .mockAny(), previous: first)

        // Then
        #expect(first.needsRetry)
        #expect(second.needsRetry)
        #expect(first.responseCode == 503)
        #expect(second.responseCode == 503)
        #expect(second.attempt == 1)
        #expect(reconciliationEvents == [events, events])
        #expect(uploadedEvents == [[events[1]], [events[1]]])
        #expect(reconciliationExecutions.map(\.attempt) == [0, 1])
        #expect(reconciliationExecutions.map(\.previousResponseCode) == [nil, 503])
        #expect(uploadExecutions.map(\.attempt) == [0, 1])
        #expect(uploadExecutions.map(\.previousResponseCode) == [nil, 503])
        #expect(client.requestsSent() == [
            reconciliationRequest, uploadRequest,
            reconciliationRequest, uploadRequest
        ])
    }

    private func makeUploader(
        builder: FeatureEventReconcilerMock,
        body: Data? = nil,
        reconciliationCode: Int = 200,
        uploadCode: Int = 202,
        reconciliationError: Error? = nil
    ) -> (DataUploader, HTTPClientMock) {
        let client = HTTPClientMock { request in
            if request == reconciliationRequest {
                if let error = reconciliationError {
                    return .failure(error)
                }
                return .success((.mockResponseWith(statusCode: reconciliationCode), body))
            }
            return .success((.mockResponseWith(statusCode: uploadCode), nil))
        }
        return (DataUploader(httpClient: client, requestBuilder: builder, featureName: .mockAny()), client)
    }
}
