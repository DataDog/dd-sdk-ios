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
/// single tracer (`runtimeID`). Payloads of whole buckets take one per built request, so retries
/// of the same batch get distinct sequence numbers, which is acceptable because the value is used
/// for identification, not for stats aggregation. A split bucket takes one when it is split and
/// keeps it in every request and retry, so its pieces stay one payload.
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

        // A batch can mix buckets flushed under different deployment identities, for example when
        // it spans an app upgrade. `env`, `version` and `service` live on `ClientStatsPayload`, not
        // on the bucket, so whole buckets are grouped by identity into one client payload each.
        //
        // Each split gets its own client payload, with the runtime ID and sequence number assigned
        // when it was split, as the agent does for fragments of one payload. Its pieces hold disjoint
        // groups, so those in this batch are merged back into one bucket. The same window can be
        // exported more than once, and each export stays separate. Insertion order is preserved so
        // payloads stay stable.
        var payloads: [ClientPayloadDraft] = []
        var wholeBucketPayloads: [DeploymentIdentity: Int] = [:]
        var splitPayloads: [ExportedBucket.Piece: Int] = [:]
        for bucket in decoded {
            // Buckets written before this field existed fall back to the upload-time context,
            // which is the previous behaviour and better than dropping the batch.
            let identity = DeploymentIdentity(
                env: bucket.env ?? context.env,
                version: bucket.version ?? context.version,
                service: bucket.service ?? context.service
            )
            let wireBucket = ClientStatsBucket(bucket)
            if let piece = bucket.piece {
                if let index = splitPayloads[piece], let existing = payloads[index].buckets.first {
                    payloads[index].buckets = [
                        ClientStatsBucket(
                            start: existing.start,
                            duration: existing.duration,
                            stats: existing.stats + wireBucket.stats
                        )
                    ]
                    payloads[index].receivedPieces += 1
                } else {
                    splitPayloads[piece] = payloads.count
                    payloads.append(ClientPayloadDraft(identity: identity, piece: piece, buckets: [wireBucket], receivedPieces: 1))
                }
            } else if let index = wholeBucketPayloads[identity] {
                payloads[index].buckets.append(wireBucket)
            } else {
                wholeBucketPayloads[identity] = payloads.count
                payloads.append(ClientPayloadDraft(identity: identity, piece: nil, buckets: [wireBucket], receivedPieces: 0))
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
                runtimeID: draft.piece?.runtimeID ?? runtimeID,
                sequenceNumber: draft.piece?.sequence ?? sequenceNumberProvider.next(),
                stats: draft.buckets
            )
        }
        // `SplitPayload` marks a payload split across requests, which happens only when a split's
        // pieces did not all land in this batch.
        let isSplit = payloads.contains { draft in draft.piece.map { draft.receivedPieces < $0.count } ?? false }
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

    /// A client payload being assembled from a batch: whole buckets of one identity, or the pieces of
    /// one split found in this batch.
    private struct ClientPayloadDraft {
        let identity: DeploymentIdentity
        let piece: ExportedBucket.Piece?
        var buckets: [ClientStatsBucket]
        var receivedPieces: Int
    }
}
