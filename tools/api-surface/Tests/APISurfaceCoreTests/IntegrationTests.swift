/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import APISurfaceCore

class IntegrationTests: XCTestCase {
    func testCreatingSurfaceForFixtureLibraries() throws {
        var outputs: [String] = []
        APISurfaceCore.printFunction = { outputs.append($0) }

        // Given
        let command = try SPMLibrarySurfaceCommand.parse([
            "--library-name", "Fixture1",
            "--library-name", "Fixture2",
            "--path", fixturesPackageFolder().path
        ])

        // When
        try command.run()

        // Then
        XCTAssertEqual(
            outputs.joined(separator: "\n"),
            """
            # ----------------------------------
            # API surface for Fixture1:
            # ----------------------------------

            public class Car
               public enum Manufacturer: String
                  case manufacturer1
                  case manufacturer2
                  case manufacturer3
               public init(manufacturer: Manufacturer)
               public func startEngine() -> Bool
               public func stopEngine() -> Bool
            public extension Car
               var price: Int


            # ----------------------------------
            # API surface for Fixture2:
            # ----------------------------------

            public class Car
               public enum Manufacturer: String
                  case manufacturer1
                  case manufacturer2
                  case manufacturer3
               public init(manufacturer: Manufacturer)
               public func startEngine() -> Bool
               public func stopEngine() -> Bool
            public extension Car
               var price: Int
            → extension String
               public func foo()
            public extension Int
               func bar()
            """
        )
    }
}

/// Resolves the url to `Fixtures` folder.
private func fixturesPackageFolder() -> URL {
    var currentFolder = URL(fileURLWithPath: #file).deletingLastPathComponent()

    while currentFolder.pathComponents.count > 0 {
        if FileManager.default.fileExists(atPath: currentFolder.appendingPathComponent("Package.swift").path) {
            return currentFolder.appendingPathComponent("Fixtures")
        } else {
            currentFolder.deleteLastPathComponent()
        }
    }

    fatalError("Cannot resolve the URL to folder containing `Package.swift`.")
}
