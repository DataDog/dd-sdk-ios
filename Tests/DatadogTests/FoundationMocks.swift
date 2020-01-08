import Foundation

/*
 A collection of mocks for different `Foundation` types. The convention we use is to extend
 types with static factory function prefixed with "mock". For example:
 
 ```
 extension URL {
    static func mockAny() -> URL {
        // ...
    }
 }
 
 extension URLSession {
    static func mockDeliverySuccess(data: Data, response: HTTPURLResponse) -> URLSessionMock {
        // ...
    }
 }
 ```
 
 Other conventions to follow:
 * Use the name `mockAny()` to name functions that return any value of given type.
 * Use descriptive function and parameter names for functions that configure the object for particular scenario.
 * Always use the minimal set of parameters which is required by given mock scenario.
 
 */

// MARK: - Basic types

extension Data {
    static func mockAny() -> Data {
        return Data()
    }

    static func mockRepeating(byte: UInt8, times count: Int) -> Data {
        return Data(repeating: byte, count: count)
    }
}

extension Array where Element == Data {
    /// Returns chunks of mocked data. Accumulative size of all chunks equals `totalSize`.
    static func mockChunksOf(totalSize: UInt64) -> [Data] {
        var chunks: [Data] = []
        var bytesWritten: UInt64 = 0

        while bytesWritten < totalSize {
            let bytesLeft = totalSize - bytesWritten
            let nextChunkSize: Int = bytesLeft > Int.max ? Int.max : Int(bytesLeft) // prevent `Int` overflow
            chunks.append(.mockRepeating(byte: 0x1, times: nextChunkSize))
            bytesWritten += UInt64(nextChunkSize)
        }

        return chunks
    }
}

extension Date {
    static func mockAny() -> Date {
        return Date(timeIntervalSinceReferenceDate: 1)
    }

    static func mockRandomInThePast() -> Date {
        return Date(timeIntervalSinceReferenceDate: TimeInterval.random(in: 0..<Date().timeIntervalSinceReferenceDate))
    }

    static func mockSpecificUTCGregorianDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = second
        dateComponents.timeZone = TimeZone(abbreviation: "UTC")
        dateComponents.calendar = Calendar(identifier: .gregorian)
        return dateComponents.date!
    }

    static func mockDecember15th2019At10AMUTC(addingTimeInterval timeInterval: TimeInterval = 0) -> Date {
        return mockSpecificUTCGregorianDate(year: 2_019, month: 12, day: 15, hour: 10)
            .addingTimeInterval(timeInterval)
    }
}

extension URL {
    static func mockAny() -> URL {
        return URL(string: "https://www.datadoghq.com")!
    }
}

extension String {
    static func mockRandom(length: Int = 10) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}

struct ErrorMock: Error {
    let description: String

    init(_ description: String = "") {
        self.description = description
    }
}

// MARK: - HTTP and URLSession

class URLSessionDataTaskMock: URLSessionDataTask {
    private let closure: () -> Void

    init(closure: @escaping () -> Void) {
        self.closure = closure
    }

    override func resume() {
        closure()
    }
}

/// Mocked `URLSession` which returns given `data`, `urlResponse` or `error`.
class URLSessionMock: URLSession {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    var data: Data?
    var urlResponse: URLResponse?
    var error: Error?

    override func dataTask(with request: URLRequest, completionHandler: @escaping CompletionHandler) -> URLSessionDataTask {
        let data = self.data
        let urlResponse = self.urlResponse
        let error = self.error

        return URLSessionDataTaskMock { completionHandler(data, urlResponse, error) }
    }
}

/// Mocked `URLSession` which notifies sent requests on `requestSent` callback.
class URLSessionRequestCapturingMock: URLSession {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    var requestSent: ((URLRequest) -> Void)?

    override func dataTask(with request: URLRequest, completionHandler: @escaping CompletionHandler) -> URLSessionDataTask {
        return URLSessionDataTaskMock { [unowned self] in self.requestSent?(request) }
    }
}

extension URLSession {
    static func mockDeliverySuccess(data: Data, response: HTTPURLResponse) -> URLSessionMock {
        let session = URLSessionMock()
        session.data = data
        session.urlResponse = response
        session.error = nil
        return session
    }

    static func mockDeliveryFailure(error: Error) -> URLSessionMock {
        let session = URLSessionMock()
        session.data = nil
        session.urlResponse = nil
        session.error = error
        return session
    }

    static func mockRequestCapture(captureBlock: @escaping (URLRequest) -> Void) -> URLSessionRequestCapturingMock {
        let session = URLSessionRequestCapturingMock()
        session.requestSent = captureBlock
        return session
    }
}

extension HTTPURLResponse {
    static func mockAny() -> HTTPURLResponse {
        return HTTPURLResponse(url: .mockAny(), statusCode: 1, httpVersion: nil, headerFields: nil)!
    }

    static func mockResponseWith(statusCode: Int) -> HTTPURLResponse {
        return HTTPURLResponse(url: .mockAny(), statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}

extension URLRequest {
    static func mockAny() -> URLRequest {
        return URLRequest(url: .mockAny())
    }
}
