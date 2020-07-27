/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest

/// Provides set of assertions for single `RUMEvent<DM: RUMDataModel>` JSON object and collection of `[RUMEvent<DM: RUMDataModel>]`.
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
    ///
    class func fromNewlineSeparatedJSONObjectsData(_ data: Data) throws -> [RUMEventMatcher] {
        let separator = "\n".data(using: .utf8)![0]
        let spansData = data.split(separator: separator).map { Data($0) }
        return try spansData.map { spanJSONData in try RUMEventMatcher.fromJSONObjectData(spanJSONData) }
    }

    private let jsonMatcher: JSONDataMatcher
    private let jsonData: Data
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

    func model<DM: Decodable>() throws -> DM {
        return try jsonDataDecoder.decode(DM.self, from: jsonData)
    }

    func model<DM: Decodable>(ofType type: DM.Type, matches matcher: (DM) -> Void) throws {
        let model = try jsonDataDecoder.decode(DM.self, from: jsonData)
        matcher(model)
    }

    func model<DM: Decodable>(isTypeOf type: DM.Type) -> Bool {
        return (try? model() as DM) != nil
    }

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
}

extension RUMEventMatcher: CustomStringConvertible {
    /// Returns prety JSON representation of this matcher. Handy for debugging with `po matcher`.
    var description: String {
        do {
            let jsonObject = try jsonData.toJSONObject()
            let prettyPrintedJSONData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
            return prettyPrintedJSONData.utf8String
        } catch {
            return "Cannot build pretty JSON: \(error)"
        }
    }
}

func XCTAssertValidRumUUID(_ string: String?, file: StaticString = #file, line: UInt = #line) {
    guard let string = string else {
        XCTFail("`nil` is not valid RUM UUID", file: file, line: line)
        return
    }
    let regex = #"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"#
    XCTAssertNotNil(
        string.range(of: regex, options: .regularExpression, range: nil, locale: nil),
        "\(string) is not valid RUM UUID - it doesn't match \(regex)",
        file: file,
        line: line
    )
}
