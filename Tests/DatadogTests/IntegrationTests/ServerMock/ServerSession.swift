import Foundation
@testable import Datadog

/// Request received by server.
protocol ServerRequest {
    init(body: Data)
}

/// Current server session recorded since `server.start()` call.
struct ServerSession<R: ServerRequest> {
    let recordedRequests: [R]

    init(recordedIn directory: Directory) throws {
        let orderedRequestFiles = try directory.files()
            .filter { file in file.name.hasPrefix("request") }
            .sorted { file1, file2 in file1.name < file2.name }

        self.recordedRequests = try orderedRequestFiles
            .map { file in R(body: try file.read()) }
    }
}
