import Foundation
import XCTest

/// Single logs request recorded by `ServerMock`.
struct LogsRequest: ServerRequest {
    let body: Data

    /// Retrieves separate log's JSONs from request body.
    func getLogJSONs(file: StaticString = #file, line: UInt = #line) throws -> [[String: Any]] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: body, options: []) as? [[String: Any]] else {
            XCTFail("Cannot decode aray of log JSONs from request body.", file: file, line: line)
            return []
        }

        return jsonArray
    }
}
