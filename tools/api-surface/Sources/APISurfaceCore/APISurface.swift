/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import SourceKittenFramework

public struct APISurfaceError: Error, CustomStringConvertible {
    public let description: String
}

public class APISurface {
    private let moduleInterface: ModuleInterface
    private let printer = ModuleInterfacePrinter()

    // MARK: - Initialization

    public convenience init(forWorkspaceNamed workspaceName: String, scheme: String, inPath path: String) throws {
        try self.init(
            module: Module(
                xcodeBuildArguments: [
                    "-workspace", workspaceName,
                    "-scheme", scheme
                ],
                inPath: path
            )
        )
    }

    public convenience init(forSPMModuleNamed spmModuleName: String, inPath path: String) throws {
        try self.init(
            module: Module(
                spmName: spmModuleName,
                inPath: path
            )
        )
    }

    private init(module: Module?) throws {
        guard let module = module else {
            throw APISurfaceError(description: "Failed to generate module interface.")
        }
        self.moduleInterface = try ModuleInterface(module: module)
    }

    // MARK: - Output

    public func print() -> String {
        printer.print(moduleInterface: moduleInterface)
    }
}
