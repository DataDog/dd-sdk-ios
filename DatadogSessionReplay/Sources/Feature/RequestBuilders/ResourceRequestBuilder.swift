/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal struct ResourceRequestBuilder: FeatureEventReconciler {
    struct Response: Decodable {
        let storedResourceIDs: Set<String>

        private enum CodingKeys: String, CodingKey {
            case storedResourceIDs = "stored_resource_ids"
        }
    }

    /// Custom URL for uploading data to.
    let customUploadURL: URL?
    /// Sends telemetry through sdk core.
    let telemetry: Telemetry
    /// Builds multipart form for request's body.
    let multipartBuilder: MultipartFormDataBuilder

    /// Stores resource identifiers confirmed to be available in the backend
    private let availabilityStore: ResourceAvailabilityStore

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        customUploadURL: URL?,
        availabilityStore: ResourceAvailabilityStore,
        telemetry: Telemetry,
        multipartBuilder: MultipartFormDataBuilder = MultipartFormData(),
    ) {
        self.customUploadURL = customUploadURL
        self.availabilityStore = availabilityStore
        self.telemetry = telemetry
        self.multipartBuilder = multipartBuilder
    }

    // MARK: - FeatureRequestBuilder

    func request(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> URLRequest {
        let resources = try events.map { event in
            try decoder.decode(EnrichedResource.self, from: event.data)
        }
        return try createRequest(resources: resources, context: context, execution: execution)
    }

    // MARK: - FeatureEventReconciler

    func reconciliation(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> EventReconciliation {
        let resourceRefs = try events.resourceRefs(using: decoder)

        guard let applicationID = resourceRefs.applicationID else {
            return .resolved
        }

        if availabilityStore.contains(
            allOf: resourceRefs.lazy.map(\.identifier),
            forApplicationID: applicationID
        ) {
            return .resolved
        }

        // TODO: PANA-9417 Build the reconciliation request for the entire batch.
        return .skip
    }

    func response(from data: Data?, with response: HTTPURLResponse) throws -> Response {
        guard let data else {
            throw InternalError(description: "Resource reconciliation response is missing its body.")
        }
        return try decoder.decode(Response.self, from: data)
    }

    func events(from events: [Event], using response: Response) throws -> [Event] {
        let resourceRefs = try events.resourceRefs(using: decoder)

        guard let applicationID = resourceRefs.applicationID else {
            return events
        }

        availabilityStore.insert(response.storedResourceIDs, forApplicationID: applicationID)

        return zip(events, resourceRefs).compactMap { event, resource in
            response.storedResourceIDs.contains(resource.identifier) ? nil : event
        }
    }

    private func createRequest(resources: [EnrichedResource], context: DatadogContext, execution: ExecutionContext) throws -> URLRequest {
        var multipart = multipartBuilder

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: execution.retryQueryItems,
            headers: [
                .contentTypeHeader(contentType: .multipartFormData(boundary: multipart.boundary)),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device,
                    os: context.os
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ],
            telemetry: telemetry
        )

        resources.forEach {
            multipart.addFormData(
                name: "image",
                filename: $0.identifier,
                data: $0.data,
                mimeType: $0.mimeType
            )
        }
        if let context = resources.first?.context {
            let data = try encoder.encode(context)
            multipart.addFormData(
                name: "event",
                filename: "blob",
                data: data,
                mimeType: "application/json"
            )
        }

        return builder.uploadRequest(with: multipart.build(), compress: true)
    }

    private func url(with context: DatadogContext) -> URL {
        customUploadURL ?? context.site.endpoint.appendingPathComponent("api/v2/replay")
    }
}

private struct ResourceRef: Decodable {
    let identifier: String
    let context: EnrichedResource.Context
}

extension Array where Element == Event {
    fileprivate func resourceRefs(using decoder: JSONDecoder) throws -> [ResourceRef] {
        try self.map { event in
            try decoder.decode(ResourceRef.self, from: event.data)
        }
    }
}

extension Array where Element == ResourceRef {
    fileprivate var applicationID: String? {
        // Assume a single application ID per resource batch.
        // Reenabling RUM with a different ID while Session Replay is active is technically possible but unsupported.
        first?.context.application.id
    }
}
#endif
