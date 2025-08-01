/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import CoreGraphics
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal struct DisplayListContents: Hashable {
    private enum Constants {
        static let cls: AnyClass? = NSClassFromString("RBMovedDisplayListContents")
        static let renderInContextOptions: Selector = NSSelectorFromString("renderInContext:options:")
        static let boundingRectKey = "boundingRect"
        static let rasterizationScaleKey = "rasterizationscale"
    }

    private let nsObject: NSObject

    init?(_ nsObject: NSObject) {
        guard
            let cls = Constants.cls,
            type(of: nsObject).isSubclass(of: cls),
            nsObject.responds(to: Constants.renderInContextOptions)
        else {
            return nil
        }

        self.nsObject = nsObject
    }

    var bounds: CGRect? {
        nsObject.value(forKey: Constants.boundingRectKey) as? CGRect
    }

    func render(in context: CGContext, scale: CGFloat) {
        nsObject.perform(
            Constants.renderInContextOptions,
            with: context,
            with: [Constants.rasterizationScaleKey: scale]
        )
    }

    static func == (lhs: DisplayListContents, rhs: DisplayListContents) -> Bool {
        lhs.nsObject.isEqual(rhs.nsObject)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(nsObject.hash)
    }
}

#endif
