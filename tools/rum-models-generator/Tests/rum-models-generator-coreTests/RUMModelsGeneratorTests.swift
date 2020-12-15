/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class RUMModelsGeneratorTests: XCTestCase {
    private func fixtureURL(_ filePath: String) -> URL {
        return resolveSwiftPackageFolder()
            .appendingPathComponent("Tests")
            .appendingPathComponent("rum-models-generator-coreTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(filePath)
    }

    func testGeneratingRUMDataModels() throws {
        let schemas = RUMJSONSchemaFiles(
            commonSchema: try File(url: fixtureURL("Input/_common-schema.json")),
            actionSchema: try File(url: fixtureURL("Input/action-schema.json")),
            errorSchema: try File(url: fixtureURL("Input/error-schema.json")),
            longTaskSchema: try File(url: fixtureURL("Input/long_task-schema.json")),
            resourceSchema: try File(url: fixtureURL("Input/resource-schema.json")),
            viewSchema: try File(url: fixtureURL("Input/view-schema.json"))
        )

        let generator = RUMModelsGenerator()

        let receivedOutput = try generator.printRUMModels(for: schemas)
        let expectedOutput = try String(contentsOf: fixtureURL("Output/RUMDataModels.swift"))

        XCTAssertEqual(expectedOutput, receivedOutput)
    }
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

    fatalError("Cannot resolve the URL to folder containing `Package.swif`.")
}
