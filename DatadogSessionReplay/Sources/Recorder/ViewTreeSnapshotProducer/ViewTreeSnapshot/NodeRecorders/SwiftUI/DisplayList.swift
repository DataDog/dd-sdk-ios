/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI
import UIKit
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
internal struct DisplayList {
    internal struct Identity: Hashable {
        let value: UInt32
    }

    internal struct Seed: Hashable {
        let value: UInt16
    }

    internal struct ViewRenderer {
        let renderer: ViewUpdater
    }

    internal struct ViewUpdater {
        internal struct ViewCache {
            internal struct Key: Hashable {
                let id: Index.ID
            }

            let map: [ViewCache.Key: ViewInfo]
        }

        internal struct ViewInfo {
            /// The container view frame in this view coordinate space
            let frame: CGRect

            /// Original view's `.backgorundColor`.
            let backgroundColor: CGColor?

            /// Original view's `layer.borderColor`.
            let borderColor: CGColor?

            /// Original view's `layer.borderWidth`.
            let borderWidth: CGFloat

            /// Original view's `layer.cornerRadius`.
            let cornerRadius: CGFloat

            /// Original view's `.alpha` (between `0.0` and `1.0`).
            let alpha: CGFloat

            /// Original view's `.isHidden`.
            let isHidden: Bool

            /// Original view's `.intrinsicContentSize`.
            let intrinsicContentSize: CGSize
        }

        let viewCache: ViewCache
        let lastList: DisplayList.Lazy
    }

    internal struct Index {
        internal struct ID: Hashable {
            let identity: Identity
        }
    }

    internal enum Effect {
        case identify
        case clip(SwiftUI.Path, SwiftUI.FillStyle)
        case filter(GraphicsFilter)
        case platformGroup
        case unknown
    }

    internal struct Content {
        internal enum Value {
            case shape(SwiftUI.Path, ResolvedPaint, SwiftUI.FillStyle)
            case text(StyledTextContentView, CGSize)
            case platformView
            case color(Color._Resolved)
            case image(GraphicsImage)
            case drawing(AnyImageRepresentable)
            case unknown
        }

        let seed: Seed
        let value: Value
    }

    internal struct Item {
        internal enum Value {
            case effect(Effect, DisplayList)
            case content(Content)
            case unknown
        }

        let identity: Identity
        let frame: CGRect
        let value: Value
    }

    let items: [Item]
}

#endif
