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
public class RUMEventMatcher {
    // MARK: - Initialization

    /// Returns "RUM event" matcher for data representing JSON string:
    public class func fromJSONObjectData(_ data: Data) throws -> RUMEventMatcher {
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
    public class func fromNewlineSeparatedJSONObjectsData(_ data: Data, eventsPatch: ((Data) throws -> Data)? = nil) throws -> [RUMEventMatcher] {
        let separator = "\n".data(using: .utf8)![0]
        var eventsData = data.split(separator: separator).map { Data($0) }
        if let patch = eventsPatch {
            eventsData = try eventsData.map { try patch($0) }
        }
        return try eventsData.map { eventJSONData in try RUMEventMatcher.fromJSONObjectData(eventJSONData) }
    }

    public let jsonData: Data
    public let jsonMatcher: JSONDataMatcher

    private let jsonDataDecoder = JSONDecoder()

    private init(with jsonData: Data) throws {
        self.jsonMatcher = JSONDataMatcher(from: try jsonData.toJSONObject())
        self.jsonData = jsonData
    }

    // MARK: - Full match

    public func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        try jsonMatcher.assertItFullyMatches(jsonString: jsonString, file: file, line: line)
    }

    // MARK: - Partial matches

    public func model<DM: Decodable>(file: StaticString = #file, line: UInt = #line) throws -> DM {
        do {
            let model = try jsonDataDecoder.decode(DM.self, from: jsonData)
            return model
        } catch {
            XCTFail("\(error)", file: file, line: line)
            throw error
        }
    }

    public func model<DM: Decodable>(ofType type: DM.Type, file: StaticString = #file, line: UInt = #line, matches matcher: (DM) -> Void) throws {
        do {
            let model = try jsonDataDecoder.decode(DM.self, from: jsonData)
            matcher(model)
        } catch {
            XCTFail("\(error)", file: file, line: line)
            throw error
        }
    }

    public func model<DM: Decodable>(isTypeOf type: DM.Type) -> Bool {
        return (try? jsonDataDecoder.decode(DM.self, from: jsonData)) != nil
    }

    public func eventType()            throws -> String { try jsonMatcher.value(forKeyPath: "type") }

    public func sessionHasReplay()     throws -> Bool? { try jsonMatcher.valueOrNil(forKeyPath: "session.has_replay") }

    public func userID()               throws -> String { try jsonMatcher.value(forKeyPath: "usr.id") }
    public func userName()             throws -> String { try jsonMatcher.value(forKeyPath: "usr.name") }
    public func userEmail()            throws -> String { try jsonMatcher.value(forKeyPath: "usr.email") }

    public func networkReachability()            throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.reachability") }
    public func networkAvailableInterfaces()     throws -> [String] { try jsonMatcher.value(forKeyPath: "meta.network.client.available_interfaces") }
    public func networkConnectionSupportsIPv4()  throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.supports_ipv4") }
    public func networkConnectionSupportsIPv6()  throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.supports_ipv6") }
    public func networkConnectionIsExpensive()   throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.is_expensive") }
    public func networkConnectionIsConstrained() throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.is_constrained") }

    public func mobileNetworkCarrierName()            throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.name") }
    public func mobileNetworkCarrierISOCountryCode()  throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.iso_country") }
    public func mobileNetworkCarrierRadioTechnology() throws -> String { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.technology") }
    public func mobileNetworkCarrierAllowsVoIP()      throws -> Bool { try jsonMatcher.value(forKeyPath: "meta.network.client.sim_carrier.allows_voip") }

    public func attribute<T: Equatable>(forKeyPath keyPath: String) throws -> T {
        return try jsonMatcher.value(forKeyPath: keyPath)
    }

    public func timing(named timingName: String) throws -> Int64 {
        return try attribute(forKeyPath: "view.custom_timings.\(timingName)")
    }
}

extension RUMEventMatcher: CustomStringConvertible {
    /// Returns pretty JSON representation of this matcher. Handy for debugging with `po matcher`.
    public var description: String {
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
    public func filterApplicationLaunchView() -> [RUMEventMatcher] {
        return filter {
            (try? $0.attribute(forKeyPath: "view.url")) != "com/datadog/application-launch/view"
        }
    }

    public func filterTelemetry() -> [RUMEventMatcher] {
        return filter {
            (try? $0.attribute(forKeyPath: "type")) != "telemetry"
        }
    }

    public func filterRUMEvents<DM: Decodable>(ofType type: DM.Type, where predicate: ((DM) -> Bool)? = nil) -> [Element] {
        return filter { matcher in matcher.model(isTypeOf: type) }
            .filter { matcher in predicate?(try! matcher.model()) ?? true }
    }

    public func lastRUMEvent<DM: Decodable>(
        ofType type: DM.Type,
        file: StaticString = #file,
        line: UInt = #line,
        where predicate: ((DM) -> Bool)? = nil
    ) throws -> Element {
        let last = filterRUMEvents(ofType: type, where: predicate).last
        return try XCTUnwrap(last, "Cannot find RUMEventMatcher matching the predicate", file: file, line: line)
    }

    public func forEachRUMEvent<DM: Decodable>(ofType type: DM.Type, body: ((DM) -> Void)) throws {
        return try filter { matcher in matcher.model(isTypeOf: type) }
            .forEach { matcher in body(try matcher.model()) }
    }

    public func compactMap<DM: Decodable>(_ type: DM.Type) throws -> [DM] {
        return try filter { $0.model(isTypeOf: type) }.map { try $0.model() }
    }
}
