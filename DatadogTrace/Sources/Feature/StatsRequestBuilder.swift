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
/// single tracer (`runtimeID`). It is incremented once per built request; retries of the same
/// batch therefore get distinct sequence numbers, which is acceptable because the value is used
/// for identification, not for stats aggregation.
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
        // on the bucket, so buckets are grouped by identity and each group becomes its own client
        // payload inside the envelope. Insertion order is preserved so payloads stay stable.
        var bucketsByIdentity: [DeploymentIdentity: [ClientStatsBucket]] = [:]
        var identityOrder: [DeploymentIdentity] = []
        for bucket in decoded {
            // Buckets written before this field existed fall back to the upload-time context,
            // which is the previous behaviour and better than dropping the batch.
            let identity = DeploymentIdentity(
                env: bucket.env ?? context.env,
                version: bucket.version ?? context.version,
                service: bucket.service ?? context.service
            )
            if bucketsByIdentity[identity] == nil {
                identityOrder.append(identity)
            }
            bucketsByIdentity[identity, default: []].append(ClientStatsBucket(bucket))
        }

        let clientStats = identityOrder.map { identity in
            ClientStatsPayload(
                // Always empty on mobile: there is no stable, meaningful device hostname
                // (and reporting one would be a privacy concern), so `DatadogContext` exposes
                // none. `Hostname` is a server-tracer field in the protobuf model; the intake
                // accepts it empty. Matches the Android SDK.
                hostname: "",
                env: identity.env,
                version: identity.version,
                service: identity.service,
                tracerVersion: context.sdkVersion,
                runtimeID: runtimeID,
                sequenceNumber: sequenceNumberProvider.next(),
                stats: bucketsByIdentity[identity] ?? []
            )
        }
        // `SplitPayload` marks a payload split across requests, which is not what this is: these
        // client payloads all travel in one request.
        let payload = StatsPayload(clientStats: clientStats, splitPayload: false)
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
}
