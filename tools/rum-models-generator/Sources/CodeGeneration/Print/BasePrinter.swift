/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Manages lines indentation for generating code.
public class BasePrinter {
    var output = ""

    public init() {}

    // MARK: - Indentation

    private(set) var indentationLevel: Int = 0

    private var currentIndentation: String {
        let indentation = "    "
        let indentations = (0..<indentationLevel).map { _ in indentation }
        return indentations.joined(separator: "")
    }

    // MARK: - Printing

    func reset() {
        output = ""
    }

    func writeLine(_ content: String) {
        output += currentIndentation + content + "\n"
    }

    func writeEmptyLine() {
        output += "\n"
    }

    func indentRight() {
        indentationLevel += 1
    }

    func indentLeft() {
        precondition(indentationLevel > 0, "Indentation level can't get negative.")
        indentationLevel = indentationLevel - 1
    }
}
