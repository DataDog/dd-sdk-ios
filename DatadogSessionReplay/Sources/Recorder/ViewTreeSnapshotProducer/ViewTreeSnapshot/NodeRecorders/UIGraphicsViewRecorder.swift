/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit
import SwiftUI

internal class UIGraphicsViewRecorder: NodeRecorder {
    let identifier: UUID

    let cls: AnyClass? = NSClassFromString("SwiftUI._UIGraphicsView")

//    let bundle = Bundle(identifier: "com.apple.SwiftUI")

    init(identifier: UUID) {
        self.identifier = identifier
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let cls = cls, type(of: view).isSubclass(of: cls) else {
            return nil
        }

//        guard Bundle(for: type(of: view)) == bundle else {
//            return nil
//        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        return IgnoredElement(subtreeStrategy: .ignore)
    }
}

#endif
