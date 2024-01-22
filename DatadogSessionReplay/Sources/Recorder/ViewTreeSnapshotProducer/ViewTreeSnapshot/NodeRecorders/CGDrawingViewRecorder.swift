/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import SwiftUI

#if canImport(CustomDump)
import CustomDump
#endif

internal class CGDrawingViewRecorder: NodeRecorder {
    let identifier = UUID()

    init() { }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard String(describing: type(of: view)) == "CGDrawingView" else {
            return nil
        }

#if canImport(CustomDump)
//        customDump(view)
#endif

        return IgnoredElement(subtreeStrategy: .ignore)
    }
}
