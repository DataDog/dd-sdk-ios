/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

/// Provides set of assertions for Log JSON object.
/// Note: this file is individually referenced by integration tests project, so no dependency on other source files should be introduced.
struct LogMatcher {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        if #available(OSX 10.14, *) {
            formatter.formatOptions.insert(.withFractionalSeconds)
        }
        return formatter
    }()

    /// Log JSON keys.
    struct JSONKey {
        static let date = "date"
        static let status = "status"
        static let message = "message"
        static let serviceName = "service"
        static let tags = "ddtags"

        // MARK: - Application info

        static let applicationVersion = "version"

        // MARK: - Logger info

        static let loggerName = "logger.name"
        static let loggerVersion = "logger.version"
        static let threadName = "logger.thread_name"

        // MARK: - User info

        static let userId = "usr.id"
        static let userName = "usr.name"
        static let userEmail = "usr.email"

        // MARK: - Network connection info

        static let networkReachability = "network.client.reachability"
        static let networkAvailableInterfaces = "network.client.available_interfaces"
        static let networkConnectionSupportsIPv4 = "network.client.supports_ipv4"
        static let networkConnectionSupportsIPv6 = "network.client.supports_ipv6"
        static let networkConnectionIsExpensive = "network.client.is_expensive"
        static let networkConnectionIsConstrained = "network.client.is_constrained"

        // MARK: - Mobile carrier info

        static let mobileNetworkCarrierName = "network.client.sim_carrier.name"
        static let mobileNetworkCarrierISOCountryCode = "network.client.sim_carrier.iso_country"
        static let mobileNetworkCarrierRadioTechnology = "network.client.sim_carrier.technology"
        static let mobileNetworkCarrierAllowsVoIP = "network.client.sim_carrier.allows_voip"
    }

    /// Allowed values for `network.client.available_interfaces` attribute.
    static let allowedNetworkAvailableInterfacesValues: Set<String> = ["wifi", "wiredEthernet", "cellular", "loopback", "other"]
    /// Allowed values for `network.client.reachability` attribute.
    static let allowedNetworkReachabilityValues: Set<String> = ["yes", "no", "maybe"]

    private let json: [String: Any]

    // MARK: - Initialization

    static func fromJSONObjectData(_ data: Data) throws -> LogMatcher {
        return self.init(from: try data.toJSONObject())
    }

    static func fromArrayOfJSONObjectsData(_ data: Data) throws -> [LogMatcher] {
        return try data.toArrayOfJSONObjects()
            .map { jsonObject in self.init(from: jsonObject) }
    }

    private init(from jsonObject: [String: Any]) {
        self.json = jsonObject
    }

    // MARK: Full match

    func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        let thisJSON = json as NSDictionary
        let theirJSON = try jsonString.data(using: .utf8)!.toJSONObject() as NSDictionary // swiftlint:disable:this force_unwrapping

        XCTAssertEqual(thisJSON, theirJSON, file: file, line: line)
    }

    // MARK: Partial matches

    func assertDate(matches datePredicate: (Date) -> Bool, file: StaticString = #file, line: UInt = #line) {
        guard let dateString = json[JSONKey.date] as? String else {
            XCTFail("Cannot decode date from log JSON: \(json).", file: file, line: line)
            return
        }
        guard let date = LogMatcher.dateFormatter.date(from: dateString) else {
            XCTFail("Date has invalid format: \(dateString).", file: file, line: line)
            return
        }
        XCTAssertTrue(datePredicate(date), file: file, line: line)
    }

    func assertServiceName(equals serviceName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.serviceName, equals: serviceName, file: file, line: line)
    }

    func assertThreadName(equals threadName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.threadName, equals: threadName, file: file, line: line)
    }

    func assertLoggerName(equals loggerName: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.loggerName, equals: loggerName, file: file, line: line)
    }

    func assertLoggerVersion(matches matcherClosure: (String) -> Bool, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKeyPath: JSONKey.loggerVersion, matches: matcherClosure, file: file, line: line)
    }

    func assertApplicationVersion(equals applicationVersion: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.applicationVersion, equals: applicationVersion, file: file, line: line)
    }

    func assertStatus(equals status: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.status, equals: status, file: file, line: line)
    }

    func assertMessage(equals message: String, file: StaticString = #file, line: UInt = #line) {
        assertValue(forKey: JSONKey.message, equals: message, file: file, line: line)
    }

    func assertUserInfo(equals userInfo: (id: String?, name: String?, email: String?)?, file: StaticString = #file, line: UInt = #line) {
        if let id = userInfo?.id { // swiftlint:disable:this identifier_name
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

    func assertAttributes(equal attributes: [String: Any], file: StaticString = #file, line: UInt = #line) {
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

    func assertTags(equal tags: [String], file: StaticString = #file, line: UInt = #line) {
        guard let tagsString = json[JSONKey.tags] as? String else {
            XCTFail("Cannot decode date from log JSON: \(json).", file: file, line: line)
            return
        }

        let matcherTags = Set(tags)
        let logTags = Set(tagsString.split(separator: ",").map { String($0) })

        XCTAssertEqual(matcherTags, logTags, file: file, line: line)
    }

    // MARK: - Generic matches

    func assertValue<T: Equatable>(forKey key: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(json[key] as? T, value, file: file, line: line)
    }

    func assertNoValue(forKey key: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(json[key], file: file, line: line)
    }

    func assertValue<T: Equatable>(forKeyPath keyPath: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        let dictionary = json as NSDictionary
        let dictionaryValue = dictionary.value(forKeyPath: keyPath)
        guard let jsonValue = dictionaryValue as? T else {
            XCTFail("Value at key path `\(keyPath)` is not of type `\(type(of: value))`: \(String(describing: dictionaryValue))", file: file, line: line)
            return
        }
        XCTAssertEqual(jsonValue, value, file: file, line: line)
    }

    func assertNoValue(forKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        let dictionary = json as NSDictionary
        XCTAssertNil(dictionary.value(forKeyPath: keyPath), file: file, line: line)
    }

    func assertValue<T: Equatable>(
        forKeyPath keyPath: String,
        matches matcherClosure: (T) -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let dictionary = json as NSDictionary
        let dictionaryValue = dictionary.value(forKeyPath: keyPath)
        guard let jsonValue = dictionaryValue as? T else {
            XCTFail(
                "Can't cast value at key path `\(keyPath)` to expected type: \(String(describing: dictionaryValue))",
                file: file,
                line: line
            )
            return
        }

        XCTAssertTrue(matcherClosure(jsonValue), file: file, line: line)
    }

    func assertValue<T>(
        forKeyPath keyPath: String,
        isTypeOf type: T.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let dictionary = json as NSDictionary
        let dictionaryValue = dictionary.value(forKeyPath: keyPath)
        XCTAssertTrue((dictionaryValue as? T) != nil, file: file, line: line)
    }
}

private extension Data {
    func toArrayOfJSONObjects(file: StaticString = #file, line: UInt = #line) throws -> [[String: Any]] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: self, options: []) as? [[String: Any]] else {
            XCTFail("Cannot decode array of JSON objects from data.", file: file, line: line)
            return []
        }

        return jsonArray
    }

    func toJSONObject(file: StaticString = #file, line: UInt = #line) throws -> [String: Any] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: self, options: []) as? [String: Any] else {
            XCTFail("Cannot decode JSON object from given data.", file: file, line: line)
            return [:]
        }

        return jsonObject
    }
}
