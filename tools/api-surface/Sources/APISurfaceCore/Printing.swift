/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import SourceKittenFramework

internal struct ModuleInterfacePrinter {
    func print(moduleInterface: ModuleInterface) -> String {
        return moduleInterface
            .fileInterfaces
            .filter { fileInterface in !fileInterface.publicInterface.isEmpty }
            .map { fileInterface in self.print(fileInterface: fileInterface) }
            .joined(separator: "\n")
    }

    private func print(fileInterface: FileInterface) -> String {
        return fileInterface
            .publicInterface
            .map { self.print(interfaceItem: $0) }
            .joined(separator: "\n")
    }

    private func print(interfaceItem: InterfaceItem) -> String {
        let inlinedDeclaration = interfaceItem.declaration
            .split(separator: "\n")
            .map { String($0).removingCommonLeadingWhitespaceFromLines() }
            .joined()

        let indentation = (0..<interfaceItem.nestingLevel)
            .map { _ in " " }
            .joined()

        return "\(indentation)\(inlinedDeclaration)"
    }
}
