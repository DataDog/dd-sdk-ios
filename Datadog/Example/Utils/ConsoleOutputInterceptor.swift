/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if DEBUG

import DatadogInternal
import UIKit

class ConsoleOutputInterceptor {
    /// Max length of output log to notify. Content exceeding this length will be truncated at beginning.
    private let maxContentsLength = 2_048

    private(set) var contents: String = ""

    var notifyContentsChange: ((String) -> Void)?

    init() {
        // Override SDK's print function to capture console output.
        consolePrint = self.process
    }

    private func process(newLog: String) {
        // send to debugger console:
        print(newLog)

        // trim, reverse and send to UI:
        let newContents = contents + "\n" + newLog
        contents = String(newContents.suffix(maxContentsLength))
        DispatchQueue.main.async {
            self.notifyContentsChange?(reverseLinesOrder(self.contents))
        }
    }
}

let consoleOutput = ConsoleOutputInterceptor()

/// Enables `ConsoleOutputInterceptor` so debugger logs can be captured and send to  UI.
func installConsoleOutputInterceptor() {
    _  = consoleOutput // invoke lazy initializer
}

func startDisplayingDebugInfo(in textView: UITextView) {
    textView.text = reverseLinesOrder(consoleOutput.contents)

    consoleOutput.notifyContentsChange = { [weak textView] newContents in
        textView?.text = newContents
    }
}

private func reverseLinesOrder(_ string: String) -> String {
    return string.split(separator: "\n").reversed().joined(separator: "\n")
}

#else

import UIKit.UITextView

func installConsoleOutputInterceptor() { }
func startDisplayingDebugInfo(in textView: UITextView) { }

#endif
