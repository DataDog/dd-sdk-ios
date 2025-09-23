/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

/// Provides set of assertions for single `Log` JSON object and collection of `[Log]`.
/// Note: this file is individually referenced by integration tests target, so no dependency on other source files should be introduced.
public class LogMatcher: JSONDataMatcher {
    /// Log JSON keys.
    public struct JSONKey {
        static let date = "date"
        static let status = "status"
        static let message = "message"
        static let service = "service"
        static let tags = "ddtags"

        // MARK: - Application info

        static let applicationVersion = "version"
        static let applicationBuildNumber = "build_version"

        // MARK: - Logger info

        static let loggerName = "logger.name"
        static let loggerVersion = "logger.version"
        static let threadName = "logger.thread_name"

        // MARK: - User info

        static let userId = "usr.id"
        static let userName = "usr.name"
        static let userEmail = "usr.email"

        // MARK: - Account info

        static let accountId = "account.id"
        static let accountName = "account.name"

        // MARK: - Network connection info

        public static let networkReachability = "network.client.reachability"
        public static let networkAvailableInterfaces = "network.client.available_interfaces"
        public static let networkConnectionSupportsIPv4 = "network.client.supports_ipv4"
        public static let networkConnectionSupportsIPv6 = "network.client.supports_ipv6"
        public static let networkConnectionIsExpensive = "network.client.is_expensive"
        public static let networkConnectionIsConstrained = "network.client.is_constrained"

        // MARK: - Mobile carrier info

        public static let mobileNetworkCarrierName = "network.client.sim_carrier.name"
        public static let mobileNetworkCarrierISOCountryCode = "network.client.sim_carrier.iso_country"
        public static let mobileNetworkCarrierRadioTechnology = "network.client.sim_carrier.technology"
        public static let mobileNetworkCarrierAllowsVoIP = "network.client.sim_carrier.allows_voip"

        // MARK: - Error info

        public static let errorKind = "error.kind"
        public static let errorMessage = "error.message"
        public static let errorStack = "error.stack"
        public static let errorFingerprint = "error.fingerprint"

        // MARK: - Dd info
        static let dd = "_dd"
        static let ddDevice = "device"
        static let ddDeviceArchitecture = "architecture"
    }

    /// Allowed values for `network.client.available_interfaces` attribute.
    public static let allowedNetworkAvailableInterfacesValues: Set<String> = ["wifi", "wiredEthernet", "cellular", "loopback", "other"]
    /// Allowed values for `network.client.reachability` attribute.
    public static let allowedNetworkReachabilityValues: Set<String> = ["yes", "no", "maybe"]

    // MARK: - Initialization

    public class func fromJSONObjectData(_ data: Data, file: StaticString = #file, line: UInt = #line) throws -> LogMatcher {
        return LogMatcher(from: try data.toJSONObject(file: file, line: line))
    }

    public class func fromArrayOfJSONObjectsData(_ data: Data, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        return try data.toArrayOfJSONObjects(file: file, line: line)
            .map { LogMatcher(from: $0) }
    }

    public class func fromLogsRequest(_ request: URLRequest, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        guard let body = try request.decompressed().httpBody else {
            XCTFail("Request has no body", file: file, line: line)
            return []
        }
        return try fromArrayOfJSONObjectsData(body)
    }

    override private init(from jsonObject: [String: Any]) {
        super.init(from: jsonObject)
    }

    // MARK: Partial matches

    public func assertDate(matches datePredicate: (Date) -> Bool, file: StaticString = #file, line: UInt = #line) {
        guard let dateString = json[JSONKey.date] as? String else {
            XCTFail("Cannot decode date from log JSON: \(json).", file: file, line: line)
            return
        }
        guard let date = date(fromISO8601FormattedString: dateString) else {
            XCTFail("Date has invalid format: \(dateString).", file: file, line: line)
            return
        }
        XCTAssertTrue(datePredicate(date), file: file, line: line)
    }

    public func assertService(equals serviceName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.service, equals: serviceName, file: file, line: line)
    }

    public func assertThreadName(equals threadName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.threadName, equals: threadName, file: file, line: line)
    }

    public func assertLoggerName(equals loggerName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.loggerName, equals: loggerName, file: file, line: line)
    }

    public func assertLoggerVersion(matches matcherClosure: (String) -> Bool, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKeyPath: JSONKey.loggerVersion, matches: matcherClosure, file: file, line: line)
    }

    public func assertApplicationVersion(equals applicationVersion: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.applicationVersion, equals: applicationVersion, file: file, line: line)
    }

    public func assertApplicationBuildNumber(equals applicationBuildNumber: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.applicationBuildNumber, equals: applicationBuildNumber, file: file, line: line)
    }

    public func assertStatus(equals status: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.status, equals: status, file: file, line: line)
    }

    public func assertMessage(equals message: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.message, equals: message, file: file, line: line)
    }

    public func assertErrorFingerprint(equals fingerprint: String) {
        assertValue(forKey: JSONKey.errorFingerprint, equals: fingerprint)
    }

    public func assertUserInfo(equals userInfo: (id: String?, name: String?, email: String?)?, file: StaticString = #file, line: UInt = #line) {
        if let id = userInfo?.id {
            assertValue(forKey: JSONKey.userId, equals: id, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.userId, file: file, line: line)
        }
        if let name = userInfo?.name {
            assertValue(forKey: JSONKey.userName, equals: name, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.userName, file: file, line: line)
        }
        if let email = userInfo?.email {
            assertValue(forKey: JSONKey.userEmail, equals: email, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.userEmail, file: file, line: line)
        }
    }

    public func assertAccountInfo(equals accountInfo: (id: String, name: String?)?, file: StaticString = #file, line: UInt = #line) {
        if let id = accountInfo?.id {
            assertValue(forKey: JSONKey.accountId, equals: id, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.accountId, file: file, line: line)
        }
        if let name = accountInfo?.name {
            assertValue(forKey: JSONKey.accountName, equals: name, file: file, line: line)
        } else {
            assertNoValue(forKey: JSONKey.accountName, file: file, line: line)
        }
    }

    public func assertAttributes(equal attributes: [String: Any], file: StaticString = #file, line: UInt = #line) {
        attributes.forEach { key, value in
            switch json[key] {
            case is String:
                XCTAssertEqual(json[key] as? String, value as? String, file: file, line: line)
            case is Int:
                XCTAssertEqual(json[key] as? Int, value as? Int, file: file, line: line)
            default:
                if json[key] == nil {
                    XCTFail("Expected `\(value)` but found `nil` for attribute `\(key)`", file: file, line: line)
                } else {
                    XCTFail("Attribute's value type: \(type(of: value)) is not supported by `LogMatcher`", file: file, line: line)
                }
            }
        }
    }

    public func assertTags(equal tags: [String], file: StaticString = #file, line: UInt = #line) {
        guard let tagsString = json[JSONKey.tags] as? String else {
            XCTFail("Cannot decode date from log JSON: \(json).", file: file, line: line)
            return
        }

        let matcherTags = Set(tags)
        let logTags = Set(tagsString.split(separator: ",").map { String($0) })

        XCTAssertEqual(matcherTags, logTags, file: file, line: line)
    }

    public func assertHasArchitecture() {
        var architecture: String?
        if let device = json[JSONKey.ddDevice] as? [String: Any] {
            architecture = device[JSONKey.ddDeviceArchitecture] as? String
        }

        XCTAssertNotNil(architecture)
    }
}

func date(fromISO8601FormattedString: String) -> Date? {
    let iso8601Formatter = DateFormatter()
    iso8601Formatter.locale = Locale(identifier: "en_US_POSIX")
    iso8601Formatter.timeZone = TimeZone(abbreviation: "UTC")!
    iso8601Formatter.calendar = Calendar(identifier: .gregorian)
    iso8601Formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" // ISO8601 format
    return iso8601Formatter.date(from: fromISO8601FormattedString)
}
