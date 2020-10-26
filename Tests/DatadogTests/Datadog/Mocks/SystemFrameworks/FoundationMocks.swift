/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

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

    static func mock(ofSize size: UInt64) -> Data {
        return mockRepeating(byte: 0x41, times: Int(size))
    }
}

extension Array where Element == Data {
    /// Returns chunks of mocked data. Accumulative size of all chunks equals `totalSize`.
    static func mockChunksOf(totalSize: UInt64, maxChunkSize: UInt64) -> [Data] {
        var chunks: [Data] = []
        var bytesWritten: UInt64 = 0

        while bytesWritten < totalSize {
            let bytesLeft = totalSize - bytesWritten
            var nextChunkSize: UInt64 = bytesLeft > Int.max ? UInt64(Int.max) : bytesLeft // prevents `Int` overflow
            nextChunkSize = nextChunkSize > maxChunkSize ? maxChunkSize : nextChunkSize // caps the next chunk to its max size
            chunks.append(.mockRepeating(byte: 0x1, times: Int(nextChunkSize)))
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

    static func mockWith(pathComponent: String) -> URL {
        return URL(string: "https://www.foo.com/")!.appendingPathComponent(pathComponent)
    }

    static func mockRandom() -> URL {
        return URL(string: "https://www.foo.com/")!
            .appendingPathComponent(
                .mockRandom(
                    among: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
                    length: 32
                )
            )
    }
}

extension String {
    static func mockAny() -> String {
        return "abc"
    }

    static func mockRandom(length: Int = 10) -> String {
        return mockRandom(
            among: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ",
            length: length
        )
    }

    static func mockRandom(among characters: String, length: Int = 10) -> String {
        return String((0..<length).map { _ in characters.randomElement()! })
    }

    static func mockRepeating(character: Character, times: Int) -> String {
        let characters = (0..<times).map { _ in character }
        return String(characters)
    }
}

extension Int {
    static func mockAny() -> Int {
        return 0
    }
}

extension Int64 {
    static func mockAny() -> Int64 {
        return 0
    }
}

extension UInt64 {
    static func mockAny() -> UInt64 {
        return 0
    }
}

extension Bool {
    static func mockAny() -> Bool {
        return false
    }
}

extension Float {
    static func mockAny() -> Float {
        return 0
    }
}

extension TimeInterval {
    static func mockAny() -> TimeInterval {
        return 0
    }

    static let distantFuture = TimeInterval(integerLiteral: .max)
}

struct ErrorMock: Error, CustomStringConvertible {
    let description: String

    init(_ description: String = "") {
        self.description = description
    }
}

struct FailingEncodableMock: Encodable {
    let errorMessage: String

    func encode(to encoder: Encoder) throws {
        throw ErrorMock(errorMessage)
    }
}

class BundleMock: Bundle {
    // swiftlint:disable identifier_name
    fileprivate var _bundlePath: String = .mockAny()
    fileprivate var _bundleIdentifier: String? = nil
    fileprivate var _CFBundleVersion: String? = nil
    fileprivate var _CFBundleShortVersionString: String? = nil
    fileprivate var _CFBundleExecutable: String? = nil
    // swiftlint:enable identifier_name

    override var bundlePath: String { _bundlePath }
    override var bundleIdentifier: String? { _bundleIdentifier }
    override func object(forInfoDictionaryKey key: String) -> Any? {
        switch key {
        case "CFBundleVersion": return _CFBundleVersion
        case "CFBundleShortVersionString": return _CFBundleShortVersionString
        case "CFBundleExecutable": return _CFBundleExecutable
        default: return super.object(forInfoDictionaryKey: key)
        }
    }
}

extension Bundle {
    static func mockAny() -> Bundle {
        return mockWith()
    }

    static func mockWith(
        bundlePath: String = .mockAny(),
        bundleIdentifier: String? = .mockAny(),
        CFBundleVersion: String? = .mockAny(),
        CFBundleShortVersionString: String? = .mockAny(),
        CFBundleExecutable: String? = .mockAny()
    ) -> Bundle {
        let mock = BundleMock()
        mock._bundlePath = bundlePath
        mock._bundleIdentifier = bundleIdentifier
        mock._CFBundleVersion = CFBundleVersion
        mock._CFBundleShortVersionString = CFBundleShortVersionString
        mock._CFBundleExecutable = CFBundleExecutable
        return mock
    }
}

// MARK: - HTTP

extension URLResponse {
    static func mockAny() -> HTTPURLResponse {
        return .mockResponseWith(statusCode: 200)
    }

    static func mockResponseWith(statusCode: Int) -> HTTPURLResponse {
        return HTTPURLResponse(url: .mockAny(), statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    static func mockWith(mimeType: String) -> HTTPURLResponse {
        return HTTPURLResponse(
            url: .mockAny(),
            mimeType: mimeType,
            expectedContentLength: -1,
            textEncodingName: nil
        )
    }
}

extension URLRequest {
    static func mockAny() -> URLRequest {
        return URLRequest(url: .mockAny())
    }

    static func mockWith(httpMethod: String) -> URLRequest {
        var request = URLRequest(url: .mockAny())
        request.httpMethod = httpMethod
        return request
    }
}

// MARK: - Process

class ProcessInfoMock: ProcessInfo {
    private var _isLowPowerModeEnabled: Bool

    init(isLowPowerModeEnabled: Bool = .mockAny()) {
        _isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    override var isLowPowerModeEnabled: Bool { _isLowPowerModeEnabled }
}

// MARK: - URLSession

extension URLSession {
    static func mockAny() -> URLSession {
        return .shared
    }
}

extension URLSessionTask {
    static func mockWith(request: URLRequest, response: HTTPURLResponse) -> URLSessionTask {
        return URLSessionTaskMock(request: request, response: response)
    }
}

extension URLSessionTaskMetrics {
    static func mockAny() -> URLSessionTaskMetrics {
        return URLSessionTaskMetrics()
    }

    @available(iOS 13, *)
    static func mockWith(
        taskInterval: DateInterval = .init(start: Date(), duration: 1),
        transactionMetrics: [URLSessionTaskTransactionMetrics] = []
    ) -> URLSessionTaskMetrics {
        return URLSessionTaskMetricsMock(
            taskInterval: taskInterval,
            transactionMetrics: transactionMetrics
        )
    }
}

extension URLSessionTaskTransactionMetrics {
    static func mockAny() -> URLSessionTaskTransactionMetrics {
        return URLSessionTaskTransactionMetrics()
    }

    /// Mocks `URLSessionTaskTransactionMetrics` by spreading out detailed values between `start` and `end`.
    @available(iOS 13, *)
    static func mockBySpreadingDetailsBetween(
        start: Date,
        end: Date,
        resourceFetchType: URLSessionTaskMetrics.ResourceFetchType = .networkLoad
    ) -> URLSessionTaskTransactionMetrics {
        let spread = end.timeIntervalSince(start)

        let fetchStartDate = start
        let domainLookupStartDate = start.addingTimeInterval(spread * 0.05) // 5%
        let domainLookupEndDate = start.addingTimeInterval(spread * 0.15) // 15%
        let connectStartDate = start.addingTimeInterval(spread * 0.15) // 15%
        let secureConnectionStartDate = start.addingTimeInterval(spread * 0.20) // 20%
        let secureConnectionEndDate = start.addingTimeInterval(spread * 0.35) // 35%
        let connectEndDate = secureConnectionEndDate
        let requestStartDate = start.addingTimeInterval(spread * 0.40) // 40%
        let responseStartDate = start.addingTimeInterval(spread * 0.50) // 50%
        let responseEndDate = end

        let countOfResponseBodyBytesAfterDecoding: Int64 = .random(in: 512..<1_024)

        return URLSessionTaskTransactionMetricsMock(
            resourceFetchType: resourceFetchType,
            fetchStartDate: fetchStartDate,
            domainLookupStartDate: domainLookupStartDate,
            domainLookupEndDate: domainLookupEndDate,
            connectStartDate: connectStartDate,
            connectEndDate: connectEndDate,
            secureConnectionStartDate: secureConnectionStartDate,
            secureConnectionEndDate: secureConnectionEndDate,
            requestStartDate: requestStartDate,
            responseStartDate: responseStartDate,
            responseEndDate: responseEndDate,
            countOfResponseBodyBytesAfterDecoding: countOfResponseBodyBytesAfterDecoding
        )
    }

    @available(iOS 13, *)
    static func mockWith(
        resourceFetchType: URLSessionTaskMetrics.ResourceFetchType = .networkLoad,
        fetchStartDate: Date? = nil,
        domainLookupStartDate: Date? = nil,
        domainLookupEndDate: Date? = nil,
        connectStartDate: Date? = nil,
        connectEndDate: Date? = nil,
        secureConnectionStartDate: Date? = nil,
        secureConnectionEndDate: Date? = nil,
        requestStartDate: Date? = nil,
        responseStartDate: Date? = nil,
        responseEndDate: Date? = nil,
        countOfResponseBodyBytesAfterDecoding: Int64 = 0
    ) -> URLSessionTaskTransactionMetrics {
        return URLSessionTaskTransactionMetricsMock(
            resourceFetchType: resourceFetchType,
            fetchStartDate: fetchStartDate,
            domainLookupStartDate: domainLookupStartDate,
            domainLookupEndDate: domainLookupEndDate,
            connectStartDate: connectStartDate,
            connectEndDate: connectEndDate,
            secureConnectionStartDate: secureConnectionStartDate,
            secureConnectionEndDate: secureConnectionEndDate,
            requestStartDate: requestStartDate,
            responseStartDate: responseStartDate,
            responseEndDate: responseEndDate,
            countOfResponseBodyBytesAfterDecoding: countOfResponseBodyBytesAfterDecoding
        )
    }
}

private class URLSessionTaskMock: URLSessionTask {
    private let _originalRequest: URLRequest
    override var originalRequest: URLRequest? { _originalRequest }

    private let _response: URLResponse
    override var response: URLResponse? { _response }

    init(request: URLRequest, response: HTTPURLResponse) {
        self._originalRequest = request
        self._response = response
    }
}

@available(iOS 13, *) // We can't rely on subclassing the `URLSessionTaskMetrics` prior to iOS 13.0
private class URLSessionTaskMetricsMock: URLSessionTaskMetrics {
    private let _taskInterval: DateInterval
    override var taskInterval: DateInterval { _taskInterval }

    private let _transactionMetrics: [URLSessionTaskTransactionMetrics]
    override var transactionMetrics: [URLSessionTaskTransactionMetrics] { _transactionMetrics }

    init(taskInterval: DateInterval, transactionMetrics: [URLSessionTaskTransactionMetrics]) {
        self._taskInterval = taskInterval
        self._transactionMetrics = transactionMetrics
    }
}

@available(iOS 13, *) // We can't rely on subclassing the `URLSessionTaskTransactionMetrics` prior to iOS 13.0
private class URLSessionTaskTransactionMetricsMock: URLSessionTaskTransactionMetrics {
    private let _resourceFetchType: URLSessionTaskMetrics.ResourceFetchType
    override var resourceFetchType: URLSessionTaskMetrics.ResourceFetchType { _resourceFetchType }

    private let _fetchStartDate: Date?
    override var fetchStartDate: Date? { _fetchStartDate }

    private let _domainLookupStartDate: Date?
    override var domainLookupStartDate: Date? { _domainLookupStartDate }

    private let _domainLookupEndDate: Date?
    override var domainLookupEndDate: Date? { _domainLookupEndDate }

    private let _connectStartDate: Date?
    override var connectStartDate: Date? { _connectStartDate }

    private let _connectEndDate: Date?
    override var connectEndDate: Date? { _connectEndDate }

    private let _secureConnectionStartDate: Date?
    override var secureConnectionStartDate: Date? { _secureConnectionStartDate }

    private let _secureConnectionEndDate: Date?
    override var secureConnectionEndDate: Date? { _secureConnectionEndDate }

    private let _requestStartDate: Date?
    override var requestStartDate: Date? { _requestStartDate }

    private let _responseStartDate: Date?
    override var responseStartDate: Date? { _responseStartDate }

    private let _responseEndDate: Date?
    override var responseEndDate: Date? { _responseEndDate }

    private let _countOfResponseBodyBytesAfterDecoding: Int64
    override var countOfResponseBodyBytesAfterDecoding: Int64 { _countOfResponseBodyBytesAfterDecoding }

    init(
        resourceFetchType: URLSessionTaskMetrics.ResourceFetchType,
        fetchStartDate: Date?,
        domainLookupStartDate: Date?,
        domainLookupEndDate: Date?,
        connectStartDate: Date?,
        connectEndDate: Date?,
        secureConnectionStartDate: Date?,
        secureConnectionEndDate: Date?,
        requestStartDate: Date?,
        responseStartDate: Date?,
        responseEndDate: Date?,
        countOfResponseBodyBytesAfterDecoding: Int64
    ) {
        self._resourceFetchType = resourceFetchType
        self._fetchStartDate = fetchStartDate
        self._domainLookupStartDate = domainLookupStartDate
        self._domainLookupEndDate = domainLookupEndDate
        self._connectStartDate = connectStartDate
        self._connectEndDate = connectEndDate
        self._secureConnectionStartDate = secureConnectionStartDate
        self._secureConnectionEndDate = secureConnectionEndDate
        self._requestStartDate = requestStartDate
        self._responseStartDate = responseStartDate
        self._responseEndDate = responseEndDate
        self._countOfResponseBodyBytesAfterDecoding = countOfResponseBodyBytesAfterDecoding
    }
}
