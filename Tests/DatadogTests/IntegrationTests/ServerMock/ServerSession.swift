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
