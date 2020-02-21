/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

#if os(macOS) // TODO: RUMM-216 Integration tests can be run on simulator and device
/// Request received by server.
struct ServerRequest {
    let body: Data
}

/// Current server session recorded since `server.start()` call.
struct ServerSession {
    let recordedRequests: [ServerRequest]

    init(recordedIn directory: Directory) throws {
        let orderedRequestFiles = try directory.files()
            .filter { file in file.name.hasPrefix("request") }
            .sorted { file1, file2 in file1.name < file2.name }

        self.recordedRequests = try orderedRequestFiles
            .map { file in try ServerRequest(body: file.read()) }
    }
}
#endif
