import Foundation
@testable import Datadog

/// Current server session recorded since `server.start()` call.
struct ServerSession {
    let recordedRequests: [RecordedRequest]

    init(recordedIn directory: Directory) throws {
        let orderedRequestFiles = try directory.files()
            .filter { file in file.name.hasPrefix("request") }
            .sorted { file1, file2 in file1.name < file2.name }

        self.recordedRequests = try orderedRequestFiles
            .map { file in RecordedRequest(body: try file.read()) }
    }
}

/// Single request recorded by `ServerMock`.
struct RecordedRequest {
    let body: Data

    init(body: Data) {
        self.body = body
    }
}

extension RecordedRequest {
    func asLogsRequest() throws -> RecordedLogsRequest {
        return try RecordedLogsRequest(request: self)
    }
}

struct RecordedLogsRequest {
    let logJSONs: [[String: Any]]

    init(request: RecordedRequest) throws {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: request.body, options: []) as? [[String: Any]] else {
            fatalError()
        }

        self.logJSONs = jsonArray
    }
}
