/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import APISurfaceCore
import ArgumentParser

class IntegrationTests: XCTestCase {
    func testCreatingSurface_ForFixtureLibraries() throws {
        // Given
        let tempDirectory = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(tempDirectory) }

        let temporaryFile = tempDirectory.appendingPathComponent("api-surface-test-output").path
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

    func testVerifySurface_ForFixtureLibraries() throws {
        // Given
        let tempDirectory = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(tempDirectory) }

        // Write expected output to a temporary file
        let referenceFile = tempDirectory.appendingPathComponent("api-surface-test-reference").path
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
        let generatedFile = tempDirectory.appendingPathComponent("api-surface-test-generated").path
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

    func testVerifySurface_Mismatch() throws {
        // Given
        let tempDirectory = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(tempDirectory) }

        // Write incorrect reference output to a temporary file
        let referenceFile = tempDirectory.appendingPathComponent("api-surface-test-reference").path
        let incorrectOutput = """
        # ----------------------------------
        # API surface for Fixture1:
        # ----------------------------------

        public class Bike
        public init()
        """
        try incorrectOutput.write(toFile: referenceFile, atomically: true, encoding: .utf8)

        // Generate API surface to temporary file
        let generatedFile = tempDirectory.appendingPathComponent("api-surface-test-generated").path
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

    func testCreatingSurface_WithObjCLanguage() throws {
        // Given
        let tempDirectory = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(tempDirectory) }

        let temporaryFile = tempDirectory.appendingPathComponent("api-surface-test-objc-output").path
        let command = try GenerateCommand.parse([
            "--library-name", "Fixture1",
            "--path", fixturesPackageFolder().path,
            "--language", "objc",
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

            public class objc_Car: NSObject
                public enum Manufacturer: Int
                    case manufacturer1
                    case manufacturer2
                    case manufacturer3
                public init(manufacturer: Manufacturer)
                public func startEngine() -> Bool
                public func stopEngine() -> Bool
                public var price: Int
            public protocol objc_CarDelegate: AnyObject
                func carDidStart(_ car: objc_Car)
                func carDidStop(_ car: objc_Car)
            public class objc_CarConfiguration: NSObject
                public var maxPrice: Int
                public init(maxPrice: Int)
                public func setDelegate(_ delegate: objc_CarDelegate?)

            """
        )
    }

    // MARK: Helpers

    /// Creates a unique temporary directory
    private func createTemporaryDirectory() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("com.datadoghq.api-surface-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        return tempDirectory
    }

    /// Cleans up a temporary directory and its contents
    private func cleanupTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
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
}
