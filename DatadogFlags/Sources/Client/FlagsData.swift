/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct FlagsData: Equatable, Codable {
    var flags: [String: FlagAssignment]
    var context: FlagsEvaluationContext
    var date: Date
    var signedPayload: PersistedSignedAssignmentPayload? = nil
}

/// Exact signed bytes and scope needed to reverify protected assignments after restart.
///
/// This type never stores the client token or customer bearer token.
internal struct PersistedSignedAssignmentPayload: Equatable, Codable {
    let protection: Flags.AssignmentProtection
    let endpoint: URL
    let environment: String
    let subject: String
    let clientTokenSHA256: String
    let authorizationBinding: AssignmentAuthorizationBinding?
    let requestBody: Data
    let requestHeaders: [String: String]
    let responseStatus: Int
    let responseBody: Data
    let responseHeaders: [String: String]
    let certificateID: String
    let rulesRevision: String
    let issuedAt: Date
    let expiresAt: Date
}
