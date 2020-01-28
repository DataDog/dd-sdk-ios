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

    static func mock(ofSize size: Int) -> Data {
        return mockRepeating(byte: 0x41, times: size)
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
        dateComponents.timeZone = .UTC
        dateComponents.calendar = .gregorian
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
    static func mockAny() -> String {
        return "abc"
    }

    static func mockRandom(length: Int = 10) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        return String((0..<length).map { _ in characters.randomElement()! })
    }

    static func mockRepeating(character: Character, times: Int) -> String {
        let characters = (0..<times).map { _ in character }
        return String(characters)
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
    /// Queue to execute work on.
    private let queue: DispatchQueue
    /// Work to execute.
    private let work: () -> Void
    /// Callback to tell `URLSession` mock that the work is done.
    private let completion: (URLSessionDataTaskMock) -> Void

    init(queue: DispatchQueue, work: @escaping () -> Void, completion: @escaping (URLSessionDataTaskMock) -> Void) {
        self.queue = queue
        self.work = work
        self.completion = completion
    }

    override func resume() {
        // The use of `unowned` is to assert that all mocked tasks complete.
        queue.async { [unowned self] in
            self.work()
            self.completion(self)
        }
    }
}

/// Apple's `URLSession` maintains a strong reference to the task until the request finishes or fails.
/// This objects allows to reproduce this behaviour for `URLSession` mocks. This object is thread-safe.
private class URLSessionDataTaskReferences {
    private let queue: DispatchQueue
    private var references: Set<URLSessionDataTaskMock> = []

    init(synchronizationQueue: DispatchQueue) {
        self.queue = synchronizationQueue
    }

    func add(_ task: URLSessionDataTaskMock) {
        queue.async { [weak self] in self?.references.insert(task) }
    }

    func remove(_ task: URLSessionDataTaskMock) {
        queue.async { [weak self] in self?.references.remove(task) }
    }
}

/// Records requests passed to `URLSessionMock`.
class URLSessionRequestRecorder {
    private var requests: [URLRequest] = []

    /// Closure called immediately after new request is recorded.
    var onNewRequest: ((URLRequest) -> Void)?

    func record(request: URLRequest) {
        requests.append(request)
        onNewRequest?(request)
    }

    var requestsSent: [URLRequest] {
        requests
    }

    func containsRequestWith(body: Data) -> Bool {
        return requests.contains { $0.httpBody == body }
    }
}

/// Mocked `URLSession` which returns given `data`, `urlResponse` or `error`.
class URLSessionMock: URLSession {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
    private let queue = DispatchQueue(label: "queue-URLSessionMock-\(UUID().uuidString)")
    private let requestsRecorder: URLSessionRequestRecorder?
    private lazy var taskReferences: URLSessionDataTaskReferences = {
        URLSessionDataTaskReferences(synchronizationQueue: queue)
    }()

    init(requestsRecorder: URLSessionRequestRecorder? = nil) {
        self.requestsRecorder = requestsRecorder
    }

    var data: Data?
    var urlResponse: URLResponse?
    var error: Error?

    override func dataTask(with request: URLRequest, completionHandler: @escaping CompletionHandler) -> URLSessionDataTask {
        let data = self.data
        let urlResponse = self.urlResponse
        let error = self.error

        let dataTask = URLSessionDataTaskMock(
            queue: queue,
            work: { [weak self] in
                self?.requestsRecorder?.record(request: request)
                completionHandler(data, urlResponse, error)
            },
            completion: { [weak self] thisTask in self?.taskReferences.remove(thisTask) }
        )
        taskReferences.add(dataTask)
        return dataTask
    }
}

extension URLSession {
    static func mockDeliverySuccess(data: Data, response: HTTPURLResponse, requestsRecorder: RequestsRecorder? = nil) -> URLSessionMock {
        let session = URLSessionMock(requestsRecorder: requestsRecorder)
        session.data = data
        session.urlResponse = response
        session.error = nil
        return session
    }

    static func mockDeliveryFailure(error: Error, requestsRecorder: RequestsRecorder? = nil) -> URLSessionMock {
        let session = URLSessionMock(requestsRecorder: requestsRecorder)
        session.data = nil
        session.urlResponse = nil
        session.error = error
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
