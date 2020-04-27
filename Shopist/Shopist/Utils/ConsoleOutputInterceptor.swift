/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if DEBUG

/// Below `@testable import` is only for SDK debug purposes, to easily override internal `consolePrint` function and display
/// the output of the `Logger` in UI. Should be never used in client's application code.
@testable import Datadog
import UIKit

class ConsoleOutputInterceptor {
    /// Max length of output log to notify. Content exceeding this length will be truncated at beginning.
    private let maxContentsLength = 2_048

    private var contents: String = ""

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
            let reversedContents = self.contents.split(separator: "\n").reversed().joined(separator: "\n")
            self.notifyContentsChange?(reversedContents)
        }
    }
}

let consoleOutput = ConsoleOutputInterceptor()

/// Enables `ConsoleOutputInterceptor` so debugger logs can be captured and send to  UI.
func installConsoleOutputInterceptor() {
    _  = consoleOutput // invoke lazy initializer
}

func startDisplayingDebugInfo(in textView: UITextView) {
    consoleOutput.notifyContentsChange = { [weak textView] newContents in
        textView?.text = newContents
    }
}

#else

import UIKit.UITextView

func installConsoleOutputInterceptor() { }
func startDisplayingDebugInfo(in textView: UITextView) { }

#endif
