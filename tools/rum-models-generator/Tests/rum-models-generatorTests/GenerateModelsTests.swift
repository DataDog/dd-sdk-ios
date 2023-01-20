/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import CodeGeneration
@testable import CodeDecoration

final class GenerateModelsTests: XCTestCase {
    /// Test made for debugging purpose.
    /// Uncomment it to run code generation for `../../../rum-events-format/rum-events-format.json`.
//    func testDebugGeneratingRUMSchemas() throws {
//        let schema = URL(fileURLWithPath: #file)
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .appendingPathComponent("rum-events-format/rum-events-format.json")
//
//        print(">>>>>>>>>>>>>>>>>> Swift >>>>>>>>>>>>>>>>>>>>>>")
//        let swiftCode = try ModelsGenerator()
//            .generateCode(from: schema)
//            .decorate(using: RUMCodeDecorator())
//            .print(using: OutputTemplate(header: "", footer: ""), and: SwiftPrinter())
//        print(swiftCode)
//        print("<<<<<<<<<<<<<<<<<< Swift <<<<<<<<<<<<<<<<<<<<<<")
//
//        print(">>>>>>>>>>>>>>>>>> ObjcInterop >>>>>>>>>>>>>>>>>>>>>>")
//        let objcInteropCode = try ModelsGenerator()
//            .generateCode(from: schema)
//            .decorate(using: RUMCodeDecorator())
//            .print(using: OutputTemplate(header: "", footer: ""), and: ObjcInteropPrinter(objcTypeNamesPrefix: "DD"))
//        print(objcInteropCode)
//        print(">>>>>>>>>>>>>>>>>> ObjcInterop >>>>>>>>>>>>>>>>>>>>>>")
//    }

    /// Test made for debugging purpose.
    /// Uncomment it to run code generation for `../../../rum-events-format/session-replay-mobile-events-format.json`.
//    func testDebugGeneratingSRSchemas() throws {
//        let schema = URL(fileURLWithPath: #file)
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .deletingLastPathComponent()
//            .appendingPathComponent("rum-events-format/session-replay-mobile-format.json")
//
//        print(">>>>>>>>>>>>>>>>>> Swift >>>>>>>>>>>>>>>>>>>>>>")
//        let swiftCode = try ModelsGenerator()
//            .generateCode(from: schema)
//            .decorate(using: SRCodeDecorator())
//            .print(
//                using: OutputTemplate(header: "", footer: ""),
//                and: SwiftPrinter(configuration: .init(accessLevel: .internal))
//            )
//        print(swiftCode)
//        print("<<<<<<<<<<<<<<<<<< Swift <<<<<<<<<<<<<<<<<<<<<<")
//    }
}
