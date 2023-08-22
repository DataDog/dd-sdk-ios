/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import SafariServices
import SwiftUI

/// The context of recording subtree hierarchy.
///
/// Some fields are mutable, so `NodeRecorders` can specialise it for their subtree traversal.
internal struct ViewTreeRecordingContext {
    /// The context of the Recorder.
    let recorder: Recorder.Context
    /// The coordinate space to convert node positions to.
    let coordinateSpace: UICoordinateSpace
    /// Generates stable IDs for traversed views.
    let ids: NodeIDGenerator
    /// Provides base64 image data with a built in caching mechanism.
    let imageDataProvider: ImageDataProviding
    /// Variable view controller related context
    var viewControllerContext: ViewControllerContext = .init()
}

internal extension ViewTreeRecordingContext {
    /// The `ViewControllerContext` struct is used for storing context-related information about the parent view controller and its type.
    struct ViewControllerContext {
        /// An enumeration representing the different types of view controllers that we handle in special way.
        enum ViewControllerType {
            case alert
            case safari
            case activity
            case swiftUI
            case other

            /// An initializer that takes a `UIViewController` and determines its corresponding `ViewControllerType`.
            ///
            /// - Parameter viewController: The `UIViewController` for which to determine the `ViewControllerType`.
            internal init(_ viewController: UIViewController?) {
                switch viewController {
                case is UIAlertController:
                    self = .alert
                case is UIActivityViewController:
                    self = .activity
                case is SFSafariViewController:
                    self = .safari
                case is AnyUIHostingViewController:
                    self = .swiftUI
                default:
                    self = .other
                }
            }
        }

        /// The parent view controller's type.
        var parentType: ViewControllerType?

        /// A boolean flag indicating whether the current view is the root view or not.
        var isRootView = false

        /// A function that checks if the current view is the root view of the specified view controller type.
        ///
        /// - Parameter of: The `ViewControllerType` to check against.
        /// - Returns: A boolean indicating whether the current view is the root view of the specified type or not.
        func isRootView(of: ViewControllerType) -> Bool {
            parentType == of && isRootView == true
        }

        /// A computed property that returns the name of the root view based on the parent view controller type.
        ///
        /// - Returns: A string representing the name of the root view, or `nil` if the current view is not the root view or the parent type is `other` or `none`.
        var name: String? {
            guard isRootView == true else {
                return nil
            }
            switch parentType {
            case .alert:
                return "Alert"
            case .activity:
                return "Activity"
            case .safari:
                return "Safari"
            case .swiftUI:
                return "SwiftUI"
            case .other,
                 .none:
                return nil
            }
        }
    }
}

private protocol AnyUIHostingViewController: AnyObject {}
@available(iOS 13.0, *)
extension UIHostingController: AnyUIHostingViewController {}
#endif
