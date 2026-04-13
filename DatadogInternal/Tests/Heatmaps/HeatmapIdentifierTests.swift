/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Testing
import DatadogInternal

struct HeatmapIdentifierTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Produces a 32 lowercase hex character string")
    func identifierIs32LowercaseHexCharacters() {
        let identifier = HeatmapIdentifier(
            elementPath: ["cls:UIButton#0"],
            screenName: "HomeViewController",
            bundleIdentifier: "com.example.app"
        )

        #expect(identifier.rawValue.count == 32)
        #expect(identifier.rawValue == identifier.rawValue.lowercased())
        #expect(identifier.rawValue.allSatisfy { $0.isHexDigit })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Same inputs produce the same identifier")
    func sameInputsProduceSameIdentifier() {
        let a = HeatmapIdentifier(
            elementPath: ["cls:UIView#0", "cls:UIButton#1"],
            screenName: "Home",
            bundleIdentifier: "com.example.app"
        )
        let b = HeatmapIdentifier(
            elementPath: ["cls:UIView#0", "cls:UIButton#1"],
            screenName: "Home",
            bundleIdentifier: "com.example.app"
        )

        #expect(a == b)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Canonical path is hashed correctly")
    func canonicalPathProducesExpectedHash() {
        let identifier = HeatmapIdentifier(
            elementPath: ["cls:UIView#0", "cls:UIButton#1"],
            screenName: "Home",
            bundleIdentifier: "com.example.app"
        )

        #expect(identifier.rawValue == "b22492581aaaae8925f9ed5c68a36118")
    }
}
