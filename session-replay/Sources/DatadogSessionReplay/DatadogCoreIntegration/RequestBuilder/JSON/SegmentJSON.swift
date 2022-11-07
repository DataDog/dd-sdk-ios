/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct SegmentJSON {
    let applicationID: String
    let sessionID: String
    let viewID: String

    let source: String

    let start: Int64
    let end: Int64
    let records: [JSONObject]
    let recordsCount: Int64
    let hasFullSnapshot: Bool

    func toJSONObject() throws -> JSONObject {
        return [
            segmentKey(.application): [applicationKey(.id): applicationID],
            segmentKey(.session): [sessionKey(.id): sessionID],
            segmentKey(.view): [viewKey(.id): viewID],
            segmentKey(.source): source,
            segmentKey(.start): start,
            segmentKey(.end): end,
            segmentKey(.hasFullSnapshot): hasFullSnapshot,
            segmentKey(.indexInView): 0,
            segmentKey(.records): records,
            segmentKey(.recordsCount): recordsCount,
        ]
    }
}

private func segmentKey(_ codingKey: SRSegment.CodingKeys) -> String { codingKey.stringValue }
private func applicationKey(_ codingKey: SRSegment.Application.CodingKeys) -> String { codingKey.stringValue }
private func sessionKey(_ codingKey: SRSegment.Session.CodingKeys) -> String { codingKey.stringValue }
private func viewKey(_ codingKey: SRSegment.View.CodingKeys) -> String { codingKey.stringValue }
