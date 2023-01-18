/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import class Foundation.Bundle
@testable import APISurfaceCore

/// API surface for `Fixtures` package
private let expectedFixturesAPISurface = """
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

final class api_surfaceTests: XCTestCase {
    func testApiSurfaceCommandLineInterface() throws {
        // Run `swift build` for `Fixtures` package
        buildFixturesPackage()

        // Run `api-surface spm --module-name Fixtures --path ./Fixtures`
        let output = try executeBinary(
            withArguments: ["spm", "--module-name", "Fixtures", "--path", resolveFixturesPackageFolder().path]
        )

        XCTAssertEqual(output, expectedFixturesAPISurface + "\n")
    }

    private func executeBinary(withArguments arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("api-surface")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class APISurfaceTests: XCTestCase {
    func testGeneratingAPISurfaceForFixturesPackage() throws {
        // Run `swift build` for `Fixtures` package
        buildFixturesPackage()

        let surface = try APISurface(
            forSPMModuleNamed: "Fixtures",
            inPath: resolveFixturesPackageFolder().path
        )

        XCTAssertEqual(surface.print(), expectedFixturesAPISurface)
    }

    /// NOTE: Use this test to debug (CMD+U) API surface for Datadog.xcworkspace
//    func testGeneratingAPISurfaceForDatadogWorkspace() throws {
//        let surface = try APISurface(
//            forWorkspaceNamed: "Datadog.xcworkspace",
//            scheme: "Datadog",
//            inPath: resolveSwiftPackageFolder().appendingPathComponent("../..").path
//        )
//
//        print(surface.print())
//    }
}

// MARK: - Helpers

/// Returns path to the built products directory.
private let productsDirectory: URL = {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return bundle.bundleURL.deletingLastPathComponent()
    }
    fatalError("couldn't find the products directory")
}()

/// Runs `swift build` for `Fixtures` package.
/// This generates necessary `.build/debug.yaml` file required by SourceKitten to parse docs for SPM module.
private func buildFixturesPackage() {
    let process = Process()
    process.currentDirectoryURL = resolveFixturesPackageFolder()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", "swift build"]
    process.launch()
    process.waitUntilExit()
}

private func resolveFixturesPackageFolder() -> URL {
    resolveSwiftPackageFolder().appendingPathComponent("Fixtures")
}

/// Resolves the url to the folder containing `Package.swift`
private func resolveSwiftPackageFolder() -> URL {
    var currentFolder = URL(fileURLWithPath: #file).deletingLastPathComponent()

    while currentFolder.pathComponents.count > 0 {
        if FileManager.default.fileExists(atPath: currentFolder.appendingPathComponent("Package.swift").path) {
            return currentFolder
        } else {
            currentFolder.deleteLastPathComponent()
        }
    }

    fatalError("Cannot resolve the URL to folder containing `Package.swift`.")
}
