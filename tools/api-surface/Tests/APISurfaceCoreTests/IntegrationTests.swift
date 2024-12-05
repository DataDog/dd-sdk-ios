/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import APISurfaceCore
import ArgumentParser

class IntegrationTests: XCTestCase {
    func testCreatingSurfaceForFixtureLibraries() throws {
        // Given
        let temporaryFile = "/tmp/api-surface-test-output"
        let command = try GenerateCommand.parse([
            "--library-name", "Fixture1",
            "--library-name", "Fixture2",
            "--path", fixturesPackageFolder().path,
            "--language", "swift",
            "--output-file", temporaryFile
        ])

        // When
        try command.run()

        // Then
        let output = try String(contentsOfFile: temporaryFile)
        XCTAssertEqual(
            output,
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
            [?] extension String
                public func foo()
            public extension Int
                func bar()

            """
        )
    }

    func testVerifySurfaceForFixtureLibraries() throws {
        // Write expected output to a temporary file
        let referenceFile = "/tmp/api-surface-test-reference"
        let expectedOutput = """
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

        """
        try expectedOutput.write(toFile: referenceFile, atomically: true, encoding: .utf8)

        // Generate API surface to temporary file
        let generatedFile = "/tmp/api-surface-test-generated"
        let generateCommand = try GenerateCommand.parse([
            "--library-name", "Fixture1",
            "--path", fixturesPackageFolder().path,
            "--language", "swift",
            "--output-file", generatedFile
        ])
        try generateCommand.run()

        // Verify the generated file matches the reference
        let verifyCommand = try VerifyCommand.parse([
            "--library-name", "Fixture1",
            "--path", fixturesPackageFolder().path,
            "--language", "swift",
            "--output-file", generatedFile,
            referenceFile
        ])
        try verifyCommand.run()
    }

    func testVerifySurfaceMismatch() throws {
        // Write incorrect reference output to a temporary file
        let referenceFile = "/tmp/api-surface-test-reference"
        let incorrectOutput = """
        # ----------------------------------
        # API surface for Fixture1:
        # ----------------------------------

        public class Bike
        public init()
        """
        try incorrectOutput.write(toFile: referenceFile, atomically: true, encoding: .utf8)

        // Generate API surface to temporary file
        let generatedFile = "/tmp/api-surface-test-generated"
        let generateCommand = try GenerateCommand.parse([
            "--library-name", "Fixture1",
            "--path", fixturesPackageFolder().path,
            "--language", "swift",
            "--output-file", generatedFile
        ])
        try generateCommand.run()

        // Verify that it detects a mismatch
        let verifyCommand = try VerifyCommand.parse([
            "--library-name", "Fixture1",
            "--path", fixturesPackageFolder().path,
            "--language", "swift",
            "--output-file", generatedFile,
            referenceFile
        ])

        XCTAssertThrowsError(try verifyCommand.run()) { error in
            if let validationError = error as? ValidationError {
                XCTAssertEqual(
                    validationError.description,
                    "❌ API surface mismatch detected!\nRun `make api-surface` locally to update reference files and commit the changes."
                )
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
}

/// Resolves the url to `Fixtures` folder.
private func fixturesPackageFolder() -> URL {
    var currentFolder = URL(fileURLWithPath: #file).deletingLastPathComponent()
    while currentFolder.pathComponents.count > 0 {
        let packageFileName = currentFolder.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageFileName.path) {
            return currentFolder.appendingPathComponent("Fixtures")
        } else {
            currentFolder.deleteLastPathComponent()
        }
    }

    fatalError("Cannot resolve the URL to folder containing `Package.swift`.")
}
