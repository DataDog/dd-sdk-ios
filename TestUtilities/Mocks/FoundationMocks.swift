/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

public protocol AnyMockable {
    static func mockAny() -> Self
}

public protocol RandomMockable {
    static func mockRandom() -> Self
}

extension Data: AnyMockable, RandomMockable {
    public static func mockAny() -> Data {
        return .mock(ofSize: 256)
    }

    public static func mockRepeating(byte: UInt8, times count: Int) -> Data {
        return Data(repeating: byte, count: count)
    }

    public static func mock<Size>(ofSize size: Size) -> Data where Size: BinaryInteger {
        return mockRepeating(byte: .mockRandom(), times: Int(size))
    }

    public static func mockRandom<Size>(ofSize size: Size) -> Data where Size: BinaryInteger {
        let count = Int(size)
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { bytes.deallocate() }
        let status = SecRandomCopyBytes(kSecRandomDefault, count, bytes)

        guard status == errSecSuccess else {
            fatalError("Failed to generate random data")
        }

        return Data(bytes: bytes, count: count)
    }

    public static func mockRandom() -> Data {
        return mockRandom(ofSize: Int.mockRandom(min: 16, max: 512))
    }
}

extension Optional: AnyMockable where Wrapped: AnyMockable {
    public static func mockAny() -> Self {
        return .some(.mockAny())
    }
}

extension Optional: RandomMockable where Wrapped: RandomMockable {
    public static func mockRandom() -> Self {
        return .some(.mockRandom())
    }
}

extension Array where Element == Data {
    /// Returns chunks of mocked data. Accumulative size of all chunks equals `totalSize`.
    public static func mockChunksOf(totalSize: UInt64, maxChunkSize: UInt64) -> [Data] {
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

extension Array {
    public func randomElements() -> [Element] {
        return compactMap { Bool.random() ? $0 : nil }
    }

    /// Chunks the array randomly, e.g.:
    ///
    ///     print([1, 2, 3, 4, 5].chunkedRandomly(numberOfChunks: 3))
    ///     // [[1], [2, 3], [4, 5]]
    ///
    public func chunkedRandomly(numberOfChunks: Int) -> [[Element]] {
        assert(numberOfChunks <= count, "`numberOfChunks` must be less than or equal to \(count)")

        var indexes = (1..<count).shuffled()
        var slices: [Int] = [0, count]
        while slices.count <= numberOfChunks {
            slices.append(indexes.removeLast())
        }
        slices.sort()

        return zip(slices, slices.dropFirst()).map { start, end in
            return Array(self[start..<end])
        }
    }
}

extension Array: AnyMockable where Element: AnyMockable {
    public static func mockAny() -> [Element] {
        return (0..<10).map { _ in .mockAny() }
    }

    public static func mockAny(count: Int) -> [Element] {
        return (0..<count).map { _ in .mockAny() }
    }
}

extension Array: RandomMockable where Element: RandomMockable {
    public static func mockRandom() -> [Element] {
        return (0..<10).map { _ in .mockRandom() }
    }

    public static func mockRandom(count: Int) -> [Element] {
        return (0..<count).map { _ in .mockRandom() }
    }
}

extension Dictionary: AnyMockable where Key: AnyMockable, Value: AnyMockable {
    public static func mockAny() -> Dictionary {
        return [Key.mockAny(): Value.mockAny()]
    }
}

extension Dictionary: RandomMockable where Key: RandomMockable, Value: RandomMockable {
    public static func mockRandom() -> Dictionary {
        return [Key.mockRandom(): Value.mockRandom()]
    }

    public static func mockRandom(count: Int) -> Dictionary {
        return (0..<count).reduce(into: [:]) { dict, _ in dict[.mockRandom()] = .mockRandom() }
    }
}

extension Set: AnyMockable where Element: AnyMockable {
    public static func mockAny() -> Set<Element> {
        return Set([Element.mockAny()])
    }
}

extension Set: RandomMockable where Element: RandomMockable {
    public static func mockRandom() -> Set<Element> {
        return Set([Element].mockRandom())
    }

    public static func mockRandom(count: Int) -> Set<Element> {
        return Set([Element].mockRandom(count: count))
    }
}

extension Date: AnyMockable, RandomMockable {
    public static func mockAny() -> Date {
        return Date(timeIntervalSinceReferenceDate: 1)
    }

    public static func mockRandom() -> Date {
        let randomTimeInterval = TimeInterval.random(in: 0..<Date().timeIntervalSince1970)
        return Date(timeIntervalSince1970: randomTimeInterval)
    }

    public static func mockRandomInThePast() -> Date {
        return Date(timeIntervalSinceReferenceDate: TimeInterval.mockRandomInThePast())
    }

    public static func mockSpecificUTCGregorianDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
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

    public static func mockDecember15th2019At10AMUTC(addingTimeInterval timeInterval: TimeInterval = 0) -> Date {
        return mockSpecificUTCGregorianDate(year: 2_019, month: 12, day: 15, hour: 10)
            .addingTimeInterval(timeInterval)
    }
}

extension TimeZone: AnyMockable {
    public static var UTC: TimeZone { TimeZone(abbreviation: "UTC")! }
    public static var EET: TimeZone { TimeZone(abbreviation: "EET")! }
    public static func mockAny() -> TimeZone { .EET }
}

extension Calendar {
    public static var gregorian: Calendar {
        return Calendar(identifier: .gregorian)
    }
}

extension URL: AnyMockable, RandomMockable {
    public static func mockAny() -> URL {
        return URL(string: "https://www.datadoghq.com")!
    }

    public static func mockWith(pathComponent: String) -> URL {
        return URL(string: "https://www.foo.com/")!.appendingPathComponent(pathComponent)
    }

    public static func mockWith(
        url: String,
        queryParams: [URLQueryItem]? = nil
    ) -> URL {
        var urlComponents = URLComponents(string: url)
        urlComponents!.queryItems = queryParams
        return urlComponents!.url!
    }

    public static func mockRandom() -> URL {
        return URL(string: "https://www.foo.com/")!
            .appendingPathComponent(
                .mockRandom(
                    among: .alphanumerics,
                    length: 32
                )
            )
    }

    public static func mockRandomPath(containing subpathComponents: [String] = []) -> URL {
        let count: Int = .mockRandom(min: 2, max: 10)
        var components: [String] = (0..<count).map { _ in
            .mockRandom(
                among: .alphanumerics,
                length: .mockRandom(min: 3, max: 10)
            )
        }
        components.insert(contentsOf: subpathComponents, at: .random(in: 0..<count))
        return URL(fileURLWithPath: "/\(components.joined(separator: "/"))")
    }
}

extension UUID: AnyMockable, RandomMockable {
    public static func mockAny() -> UUID {
        return UUID()
    }

    public static func mockRandom() -> UUID {
        return UUID()
    }
}

extension String: AnyMockable, RandomMockable {
    public static func mockAny() -> String {
        return "abc"
    }

    public static func mockRandom() -> String {
        return mockRandom(length: 10)
    }

    public static func mockRandom(length: Int) -> String {
        return mockRandom(among: .alphanumericsAndWhitespace, length: length)
    }

    public static func mockRandom(among characters: RandomStringCharacterSet, length: Int = 10) -> String {
        return characters.random(ofLength: length)
    }

    public static func mockRandom(otherThan values: Set<String> = []) -> String {
        var random: String = .mockRandom()
        while values.contains(random) { random = .mockRandom() }
        return random
    }

    public static func mockRepeating(character: Character, times: Int) -> String {
        let characters = (0..<times).map { _ in character }
        return String(characters)
    }

    public enum RandomStringCharacterSet {
        private static let alphanumericCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        private static let decimalDigitCharacters = "0123456789"

        /// Only letters and numbers (lower and upper cased).
        case alphanumerics
        /// Letters, numbers and whitespace (lower and upper cased).
        case alphanumericsAndWhitespace
        /// Only numbers.
        case decimalDigits
        /// Custom characters.
        case custom(characters: String)
        /// All Unicode scalars.
        case allUnicodes

        func random(ofLength length: Int) -> String {
            var characters: String
            switch self {
            case .alphanumerics:
                characters = RandomStringCharacterSet.alphanumericCharacters
            case .alphanumericsAndWhitespace:
                characters = RandomStringCharacterSet.alphanumericCharacters + " "
            case .decimalDigits:
                characters = RandomStringCharacterSet.decimalDigitCharacters
            case .custom(let customCharacters):
                characters = customCharacters
            case .allUnicodes:
                var view = UnicodeScalarView()
                (0..<length).forEach { _ in view.append(Unicode.Scalar.mockRandom()) }
                return String(view)
            }

            return String((0..<length).map { _ in characters.randomElement()! })
        }
    }
}

extension Character: AnyMockable, RandomMockable {
    public static func mockAny() -> Character { "c" }

    public static func mockRandom() -> Character {
        return Character(Unicode.Scalar.mockRandom())
    }
}

extension Unicode.Scalar: RandomMockable {
    public static func mockRandom() -> Self {
        // From `Unicode.Scalar.init?(_ v: UInt32))`:
        //
        // > - Parameter v: The Unicode code point to use for the scalar. The
        // > initializer succeeds if `v` is a valid Unicode scalar value---that is,
        // > if `v` is in the range `0...0xD7FF` or `0xE000...0x10FFFF`. If `v` is
        // > an invalid Unicode scalar value, the result is `nil`.
        var codePoint: UInt32 = .mockRandom(min: 0x0, max: 0x10FFFF)
        while codePoint > 0xD7FF && codePoint < 0xE000 {
            codePoint = .mockRandom(min: 0x0, max: 0x10FFFF)
        }
        return Unicode.Scalar(codePoint)! // force-unwrap as we guarantee `randomCodePoint` is correct
    }
}

extension Bool: RandomMockable {
    public static func mockRandom() -> Bool {
        return .random()
    }
}

extension Range where Bound == Int {
    static func mockRandomBetween(min: Int, max: Int) -> Range<Int> {
        let bound1: Int = .mockRandom(min: min, max: max)
        let bound2: Int = .mockRandom(min: min, max: max)
        return bound1 < bound2 ? bound1..<bound2 : bound2..<bound1
    }
}

extension FixedWidthInteger where Self: RandomMockable {
    public static func mockRandom() -> Self {
        return .random(in: min...max)
    }

    public static func mockRandom(min: Self = .min, max: Self = .max, otherThan values: Set<Self> = []) -> Self {
        var random: Self = .random(in: min...max)
        while values.contains(random) { random = .random(in: min...max) }
        return random
    }
}

extension ExpressibleByIntegerLiteral where Self: AnyMockable {
    public static func mockAny() -> Self { 0 }
}

extension UInt: AnyMockable, RandomMockable { }
extension UInt8: AnyMockable, RandomMockable { }
extension UInt16: AnyMockable, RandomMockable { }
extension UInt32: AnyMockable, RandomMockable { }
extension UInt64: AnyMockable, RandomMockable { }
extension Int: AnyMockable, RandomMockable { }
extension Int8: AnyMockable, RandomMockable { }
extension Int16: AnyMockable, RandomMockable { }
extension Int32: AnyMockable, RandomMockable { }
extension Int64: AnyMockable, RandomMockable { }

extension UInt64 {
    public static func mockRandom(otherThan value: UInt64) -> UInt64 {
        var random: UInt64 = .mockRandom()
        while random == value { random = .mockRandom() }
        return random
    }
}

extension Bool: AnyMockable {
    public static func mockAny() -> Bool {
        return false
    }
}

extension Float: AnyMockable, RandomMockable {
    public static func mockAny() -> Float {
        return 0
    }

    public static func mockRandom() -> Float {
        return .random(in: -Float(Int.min)...Float(Int.max))
    }

    public static func mockRandom(min: Float, max: Float) -> Float {
        return .random(in: min...max)
    }
}

extension Double: AnyMockable, RandomMockable {
    public static func mockAny() -> Double {
        return 0
    }

    public static func mockRandom() -> Double {
        return mockRandom(min: 0, max: .greatestFiniteMagnitude)
    }

    public static func mockRandom(min: Double, max: Double) -> Double {
        return .random(in: min...max)
    }
}

extension TimeInterval {
    public static let distantFuture = TimeInterval(integerLiteral: .max)

    public static func mockRandomInThePast() -> TimeInterval {
        return random(in: 0..<Date().timeIntervalSinceReferenceDate)
    }
}

public struct ErrorMock: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String = "") {
        self.description = description
    }
}

public struct FailingEncodableMock: Encodable {
    public let errorMessage: String

    public init(errorMessage: String) {
        self.errorMessage = errorMessage
    }

    public func encode(to encoder: Encoder) throws {
        throw ErrorMock(errorMessage)
    }
}

extension NSError: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        .init(domain: .mockAny(), code: .mockAny())
    }

    public static func mockRandom() -> Self {
        .init(domain: .mockRandom(), code: .mockRandom())
    }
}

public class BundleMock: Bundle {
    // swiftlint:disable identifier_name
    fileprivate var _bundlePath: String = .mockAny()
    fileprivate var _bundleIdentifier: String? = nil
    fileprivate var _CFBundleVersion: String? = nil
    fileprivate var _CFBundleShortVersionString: String? = nil
    fileprivate var _CFBundleExecutable: String? = nil
    // swiftlint:enable identifier_name

    public override var bundlePath: String { _bundlePath }
    public override var bundleIdentifier: String? { _bundleIdentifier }
    public override func object(forInfoDictionaryKey key: String) -> Any? {
        switch key {
        case "CFBundleVersion": return _CFBundleVersion
        case "CFBundleShortVersionString": return _CFBundleShortVersionString
        case "CFBundleExecutable": return _CFBundleExecutable
        default: return super.object(forInfoDictionaryKey: key)
        }
    }
}

extension Bundle {
    public static func mockAny() -> Bundle {
        return mockWith()
    }

    public static func mockWith(
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
    public static func mockAny() -> HTTPURLResponse {
        return .mockResponseWith(statusCode: 200)
    }

    public static func mockResponseWith(statusCode: Int) -> HTTPURLResponse {
        return HTTPURLResponse(url: .mockAny(), statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    public static func mockWith(
        statusCode: Int = 200,
        mimeType: String? = "application/json"
    ) -> HTTPURLResponse {
        let headers: [String: String] = (mimeType == nil) ? [:] : ["Content-Type": "\(mimeType!)"]
        return HTTPURLResponse(
            url: .mockAny(),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }
}

extension URLRequest: AnyMockable {
    public static func mockAny() -> URLRequest {
        return .mockWith()
    }

    public static func mockWith(httpMethod: String) -> URLRequest {
        var request = URLRequest(url: .mockAny())
        request.httpMethod = httpMethod
        return request
    }

    public static func mockWith(
        url: String,
        queryParams: [URLQueryItem]? = nil,
        httpMethod: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil
    ) -> URLRequest {
        let url: URL = .mockWith(url: url, queryParams: queryParams)
        return mockWith(url: url, httpMethod: httpMethod, headers: headers, body: body)
    }

    public static func mockWith(
        url: URL = .mockAny(),
        httpMethod: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        return request
    }
}

// MARK: - Process

public class ProcessInfoMock: ProcessInfo {
    private var _isLowPowerModeEnabled: Bool
    private var _environment: [String: String]
    private var _arguments: [String]

    public init(
        isLowPowerModeEnabled: Bool = .mockAny(),
        environment: [String: String] = [:],
        arguments: [String] = []
    ) {
        _isLowPowerModeEnabled = isLowPowerModeEnabled
        _environment = environment
        _arguments = arguments
    }

    public override var isLowPowerModeEnabled: Bool { _isLowPowerModeEnabled }

    public override var environment: [String : String] { _environment }

    public override var arguments: [String] { _arguments }

}

// MARK: - URLSession

extension URLSession {
    public static func mockAny() -> URLSession {
        return .shared
    }
}

extension URLSessionTask {
    public static func mockAny() -> URLSessionDataTask {
        return URLSessionDataTaskMock(request: .mockAny(), response: .mockAny())
    }

    public static func mockWith(request: URLRequest, response: HTTPURLResponse) -> URLSessionDataTask {
        return URLSessionDataTaskMock(request: request, response: response)
    }
}

extension URLSessionTaskMetrics {
    public static func mockAny() -> URLSessionTaskMetrics {
        return URLSessionTaskMetrics()
    }

    @available(iOS 13, *)
    public static func mockWith(
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
    public static func mockAny() -> URLSessionTaskTransactionMetrics {
        return URLSessionTaskTransactionMetrics()
    }

    /// Mocks `URLSessionTaskTransactionMetrics` by spreading out detailed values between `start` and `end`.
    @available(iOS 13, *)
    public static func mockBySpreadingDetailsBetween(
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
    public static func mockWith(
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

private class URLSessionDataTaskMock: URLSessionDataTask {
    private let _originalRequest: URLRequest
    override var originalRequest: URLRequest? { _originalRequest }
    override var currentRequest: URLRequest? { _originalRequest }

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
