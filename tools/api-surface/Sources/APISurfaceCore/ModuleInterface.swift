/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SourceKittenFramework

/// A single interface item, e.g.: class or method declaration.
internal struct InterfaceItem {
    /// Code declaration,
    /// e.g. `class Car` or `case manufacturer1` for enum.
    let declaration: String

    /// The level of nesting this item,
    /// e.g. `2` for `struct City` nested in `struct Address`.
    let nestingLevel: Int
}

/// An interface of the entire module.
internal struct ModuleInterface {
    /// List of file interfaces in this module.
    let fileInterfaces: [FileInterface]

    init(module: Module) throws {
        self.fileInterfaces = try module.docs.map { fileDocs in
            try FileInterface(docs: fileDocs)
        }
    }
}

/// An interface of a single source file.
internal struct FileInterface {
    /// List of public interface items in this file.
    let publicInterface: [InterfaceItem]

    fileprivate init(docs: SwiftDocs) throws {
        self.publicInterface = try getPublicInterfaceItems(from: docs)
    }
}
