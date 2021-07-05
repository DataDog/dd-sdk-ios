/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class RUMModelsGeneratorTests: XCTestCase {
    /// Test made for debugging purpose.
    /// Uncomment it to run code generation for `../../../rum-events-format/schemas`.
//    func testPrintDebugSchemas() throws {
//        let rumEventsFormatSchemasFolder = URL(fileURLWithPath: #file)
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .appendingPathComponent("rum-events-format/schemas", isDirectory: true)
//
//        let schemasFolderURL = URL(fileURLWithPath: rumEventsFormatSchemasFolder.absoluteString)
//
//        let schemas = try RUMJSONSchemaFiles(folder: schemasFolderURL)
//        let generator = RUMModelsGenerator()

//        print(">>>>>>>>>>>>>>>>>> Swift >>>>>>>>>>>>>>>>>>>>>>")
//        print(try generator.printRUMModels(for: schemas, using: .swift))
//        print("<<<<<<<<<<<<<<<<<< Swift <<<<<<<<<<<<<<<<<<<<<<")
//        print(">>>>>>>>>>>>>>>>>> ObjcInterop >>>>>>>>>>>>>>>>>>>>>>")
//        print(try generator.printRUMModels(for: schemas, using: .objcInterop))
//        print(">>>>>>>>>>>>>>>>>> ObjcInterop >>>>>>>>>>>>>>>>>>>>>>")
//    }
}
