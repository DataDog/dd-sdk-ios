/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Provides monotonically increasing sequence numbers for uploaded stats payloads.
///
/// The sequence number lets the intake order and uniquely identify the payloads sent by a
/// single tracer (`runtimeID`). `ClientStatsFeature` takes one for every bucket it stores, which
/// keeps it across retries and restarts. The request builder takes one only for buckets stored by
/// earlier builds, which have none.
internal final class StatsSequenceNumberProvider {
    @ReadWriteLock
    private var value: UInt64 = 0

    /// Returns the next sequence number, starting at `1` for the first call.
    func next() -> UInt64 {
        var next: UInt64 = 0
        _value.mutate {
            $0 += 1
            next = $0
        }
        return next
    }
}

/// Builds HTTP requests for uploading client-side stats to the `/api/v0.2/stats` intake.
///
/// Decodes the `ExportedBucket`s persisted by `ClientStatsFeature`, maps them onto the
/// wire-format `StatsPayload`, encodes that to MessagePack, and uploads it deflate-compressed.
internal struct StatsRequestBuilder: FeatureRequestBuilder {
    /// Custom stats intake URL, overriding the site default when set.
    let customIntakeURL: URL?
    /// Sends telemetry through the SDK core.
    let telemetry: Telemetry
    /// Identifies the tracer instance uniquely across the payloads it sends.
    let runtimeID: String
    /// Supplies the per-payload sequence number.
    let sequenceNumberProvider: StatsSequenceNumberProvider

    private let encoder = MsgPackEncoder()
    private let decoder = JSONDecoder()

    func request(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> URLRequest {
        guard !events.isEmpty else {
            throw InternalError(description: "[Trace] Client stats batch must not be empty.")
        }

        // If a stored bucket cannot be decoded there is no way to recover it, so we throw
        // and let the core drop the batch rather than uploading a partial payload.
        let decoded = try events.map { try decoder.decode(ExportedBucket.self, from: $0.data) }

        // Each stored bucket carries the identity of the client payload it belongs to: its runtime ID
        // and sequence number, assigned when it was flushed. Pieces of a split share it and hold
        // disjoint groups, so those in this batch are merged back into one bucket. Insertion order
        // is preserved, so sequence numbers increase in the order payloads were stored.
        //
        // Buckets stored by earlier builds carry no payload identity. As before, those of one
        // deployment share a client payload, with this builder's runtime ID and a new sequence number.
        var payloads: [ClientPayloadDraft] = []
        var payloadIndexes: [ExportedBucket.PayloadIdentity: Int] = [:]
        var legacyPayloadIndexes: [DeploymentIdentity: Int] = [:]
        for bucket in decoded {
            // Buckets written before this field existed fall back to the upload-time context,
            // which is the previous behaviour and better than dropping the batch.
            let identity = DeploymentIdentity(
                env: bucket.env ?? context.env,
                version: bucket.version ?? context.version,
                service: bucket.service ?? context.service
            )
            let wireBucket = ClientStatsBucket(bucket)
            if let payload = bucket.payload {
                if let index = payloadIndexes[payload] {
                    if bucket.isPartial, let existing = payloads[index].buckets.first {
                        payloads[index].buckets = [
                            ClientStatsBucket(
                                start: existing.start,
                                duration: existing.duration,
                                stats: existing.stats + wireBucket.stats
                            )
                        ]
                    } else {
                        payloads[index].buckets.append(wireBucket)
                    }
                    payloads[index].receivedPieces += 1
                } else {
                    payloadIndexes[payload] = payloads.count
                    payloads.append(ClientPayloadDraft(
                        identity: identity,
                        payload: payload,
                        buckets: [wireBucket],
                        receivedPieces: 1,
                        pieceCount: bucket.pieceCount ?? 1
                    ))
                }
            } else if let index = legacyPayloadIndexes[identity] {
                payloads[index].buckets.append(wireBucket)
            } else {
                legacyPayloadIndexes[identity] = payloads.count
                payloads.append(ClientPayloadDraft(identity: identity, payload: nil, buckets: [wireBucket], receivedPieces: 1, pieceCount: 1))
            }
        }

        let clientStats = payloads.map { draft in
            ClientStatsPayload(
                // Always empty on mobile: there is no stable, meaningful device hostname
                // (and reporting one would be a privacy concern), so `DatadogContext` exposes
                // none. `Hostname` is a server-tracer field in the protobuf model; the intake
                // accepts it empty. Matches the Android SDK.
                hostname: "",
                env: draft.identity.env,
                version: draft.identity.version,
                service: draft.identity.service,
                tracerVersion: context.sdkVersion,
                runtimeID: draft.payload?.runtimeID ?? runtimeID,
                sequenceNumber: draft.payload?.sequence ?? sequenceNumberProvider.next(),
                stats: draft.buckets
            )
        }
        // `SplitPayload` marks a payload split across requests, which happens only when some pieces of
        // a split did not land in this batch.
        let isSplit = payloads.contains { $0.receivedPieces < $0.pieceCount }
        let payload = StatsPayload(clientStats: clientStats, splitPayload: isSplit)
        let body = try encoder.encode(payload)

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [],
            headers: [
                .contentTypeHeader(contentType: .applicationMsgPack),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device,
                    os: context.os
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.ciAppOrigin ?? context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ],
            telemetry: telemetry
        )

        return builder.uploadRequest(with: body)
    }

    func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v0.2/stats")
    }

    /// A client payload being assembled from a batch.
    private struct ClientPayloadDraft {
        let identity: DeploymentIdentity
        /// `nil` for buckets stored by earlier builds.
        let payload: ExportedBucket.PayloadIdentity?
        var buckets: [ClientStatsBucket]
        var receivedPieces: Int
        /// The pieces the payload was split into, or `1` when it was not split.
        let pieceCount: Int
    }
}
