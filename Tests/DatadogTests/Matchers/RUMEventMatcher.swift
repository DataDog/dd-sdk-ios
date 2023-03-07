/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

/// Provides set of assertions for single `RUMDataModel` JSON object and collection of `[RUMDataModel]`.
/// Note: this file is individually referenced by integration tests target, so no dependency on other source files should be introduced except `RUMDataModel` implementations
/// for partial matching concrete RUM events conforming to [rum-events-format](https://github.com/DataDog/rum-events-format).
internal class RUMEventMatcher {
    // MARK: - Initialization

    /// Returns "RUM event" matcher for data representing JSON string:
    class func fromJSONObjectData(_ data: Data) throws -> RUMEventMatcher {
        return try RUMEventMatcher(with: data)
    }

    /// Returns array containing RUM event A, RUM event B RUM event Span C matchers for data representing string:
    ///
    ///     ```
    ///     { /* RUM event A json */ }
    ///     { /* RUM event B json */ }
    ///     { /* RUM event C json */ }
    ///     ```
    ///
    /// **See Also** `RUMEventMatcher.fromJSONObjectData(_:)`
    /// - Parameter data: payload data
    /// - Parameter eventsPatch: optional transformation to apply on each event within the payload before instantiating matcher (default: `nil`)
    class func fromNewlineSeparatedJSONObjectsData(_ data: Data, eventsPatch: ((Data) throws -> Data)? = nil) throws -> [RUMEventMatcher] {
        let separator = "\n".data(using: .utf8)![0]
        var eventsData = data.split(separator: separator).map { Data($0) }
        if let patch = eventsPatch {
            eventsData = try eventsData.map { try patch($0) }
        }
        return try eventsData.map { eventJSONData in try RUMEventMatcher.fromJSONObjectData(eventJSONData) }
    }

    let jsonData: Data
    let jsonMatcher: JSONDataMatcher

    private let jsonDataDecoder = JSONDecoder()

    private init(with jsonData: Data) throws {
        self.jsonMatcher = JSONDataMatcher(from: try jsonData.toJSONObject())
        self.jsonData = jsonData
    }

    // MARK: - Full match

    func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        try jsonMatcher.assertItFullyMatches(jsonString: jsonString, file: file, line: line)
    }

    // MARK: - Partial matches

    func model<DM: Decodable>(file: StaticString = #file, line: UInt = #line) throws -> DM {
        do {
            let model = try jsonDataDecoder.decode(DM.self, from: jsonData)
            return model
        } catch {
            XCTFail("\(error)", file: file, line: line)
            throw error
        }
    }

    func model<DM: Decodable>(ofType type: DM.Type, file: StaticString = #file, line: UInt = #line, matches matcher: (DM) -> Void) throws {
        do {
            let model = try jsonDataDecoder.decode(DM.self, from: jsonData)
            matcher(model)
        } catch {
            XCTFail("\(error)", file: file, line: line)
            throw error
        }
    }

    func model<DM: Decodable>(isTypeOf type: DM.Type) -> Bool {
        return (try? jsonDataDecoder.decode(DM.self, from: jsonData)) != nil
    }

    func eventType()            throws -> String { try jsonMatcher.value(forKeyPath: "type") }

    func userID()               throws -> String { try jsonMatcher.value(forKeyPath: "usr.id") }
    func userName()             throws -> String { try jsonMatcher.value(forKeyPath: "usr.name") }
    func userEmail()            throws -> String { try jsonMatcher.value(forKeyPath: "usr.email") }

    func networkReachability()            throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.reachability") }
    func networkAvailableInterfaces()     throws -> [String] { try jsonMatcher.value(forKeyPath: "meta.network.client.available_interfaces") }
    func networkConnectionSupportsIPv4()  throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.supports_ipv4") }
    func networkConnectionSupportsIPv6()  throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.supports_ipv6") }
    func networkConnectionIsExpensive()   throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.is_expensive") }
    func networkConnectionIsConstrained() throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.is_constrained") }

    func mobileNetworkCarrierName()            throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.name") }
    func mobileNetworkCarrierISOCountryCode()  throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.iso_country") }
    func mobileNetworkCarrierRadioTechnology() throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.technology") }
    func mobileNetworkCarrierAllowsVoIP()      throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.allows_voip") }

    func attribute<T: Equatable>(forKeyPath keyPath: String) throws -> T {
        return try jsonMatcher.value(forKeyPath: keyPath)
    }

    func timing(named timingName: String) throws -> Int64 {
        return try attribute(forKeyPath: "view.custom_timings.\(timingName)")
    }
}

extension RUMEventMatcher: CustomStringConvertible {
    /// Returns pretty JSON representation of this matcher. Handy for debugging with `po matcher`.
    var description: String {
        do {
            let jsonObject = try jsonData.toJSONObject()
            let prettyPrintedJSONData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
            return String(data: prettyPrintedJSONData, encoding: .utf8) ?? "Failed to build String from utf8 data"
        } catch {
            return "Cannot build pretty JSON: \(error)"
        }
    }
}

extension Array where Element == RUMEventMatcher {
    func filterApplicationLaunchView() -> [RUMEventMatcher] {
        return filter {
            (try? $0.attribute(forKeyPath: "view.url")) != "com/datadog/application-launch/view"
        }
    }

    func filterRUMEvents<DM: Decodable>(ofType type: DM.Type, where predicate: ((DM) -> Bool)? = nil) -> [Element] {
        return filter { matcher in matcher.model(isTypeOf: type) }
            .filter { matcher in predicate?(try! matcher.model()) ?? true }
    }

    func lastRUMEvent<DM: Decodable>(
        ofType type: DM.Type,
        file: StaticString = #file,
        line: UInt = #line,
        where predicate: ((DM) -> Bool)? = nil
    ) throws -> Element {
        let last = filterRUMEvents(ofType: type, where: predicate).last
        return try XCTUnwrap(last, "Cannot find RUMEventMatcher matching the predicate", file: file, line: line)
    }

    func forEachRUMEvent<DM: Decodable>(ofType type: DM.Type, body: ((DM) -> Void)) throws {
        return try filter { matcher in matcher.model(isTypeOf: type) }
            .forEach { matcher in body(try matcher.model()) }
    }

    func compactMap<DM: Decodable>(_ type: DM.Type) throws -> [DM] {
        return try filter { $0.model(isTypeOf: type) }.map { try $0.model() }
    }
}

func XCTAssertValidRumUUID(_ string: String?, file: StaticString = #file, line: UInt = #line) {
    let schemaReference = "given by https://github.com/DataDog/rum-events-format/blob/master/schemas/_common-schema.json"
    guard let string = string else {
        XCTFail("`nil` is not valid RUM UUID \(schemaReference)", file: file, line: line)
        return
    }
    let regex = #"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"#
    XCTAssertNotNil(
        string.range(of: regex, options: .regularExpression, range: nil, locale: nil),
        "\(string) is not valid RUM UUID - it doesn't match \(regex) \(schemaReference)",
        file: file,
        line: line
    )
}
