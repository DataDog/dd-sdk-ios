/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit
import WebKit

/// Builds `ViewTreeSnapshot` for given root view.
///
/// Note: This builder is used by `Recorder` on the main thread.
internal struct ViewTreeSnapshotBuilder {
    /// Records subtree of the root view.
    let viewTreeRecorder: ViewTreeRecorder
    /// Generates stable IDs for traversed views.
    let idsGenerator: NodeIDGenerator
    /// The webviews cache.
    let webViewCache: NSHashTable<WKWebView> = .weakObjects()

    /// Builds the `ViewTreeSnapshot` for given root view.
    ///
    /// - Parameter rootView: the root view
    /// - Parameter recorderContext: the context of the Recorder from the moment of requesting this snapshot
    /// - Returns: snapshot describing the view tree starting in `rootView`. All properties in snapshot nodes
    /// are computed relatively to the `rootView` (e.g. the `x` and `y` position of all descendant nodes  is given
    /// as its position in the root, no matter of nesting level).
    func createSnapshot(of rootView: UIView, with recorderContext: Recorder.Context) -> ViewTreeSnapshot {
        let context = ViewTreeRecordingContext(
            recorder: recorderContext,
            coordinateSpace: rootView,
            ids: idsGenerator,
            webViewCache: webViewCache,
            clip: rootView.bounds
        )
        let nodes = viewTreeRecorder.record(rootView, in: context)
        let snapshot = ViewTreeSnapshot(
            date: recorderContext.date.addingTimeInterval(recorderContext.viewServerTimeOffset ?? 0),
            context: recorderContext,
            viewportSize: rootView.bounds.size,
            nodes: nodes,
            webViewSlotIDs: Set(webViewCache.allObjects.map(\.hash))
        )
        return snapshot
    }
}

extension ViewTreeSnapshotBuilder {
    init(
        additionalNodeRecorders: [NodeRecorder],
        featureFlags: SessionReplay.Configuration.FeatureFlags
    ) {
        self.init(
            viewTreeRecorder: ViewTreeRecorder(
                nodeRecorders: createDefaultNodeRecorders(featureFlags: featureFlags) + additionalNodeRecorders
            ),
            idsGenerator: NodeIDGenerator()
        )
    }
}

/// An arrays of default node recorders executed for the root view-tree hierarchy.
internal func createDefaultNodeRecorders(featureFlags: SessionReplay.Configuration.FeatureFlags) -> [NodeRecorder] {
    var recorders: [NodeRecorder] = [
        UnsupportedViewRecorder(
            identifier: UUID(),
            featureFlags: featureFlags
        ),
        UIViewRecorder(identifier: UUID()),
        UILabelRecorder(identifier: UUID()),
        UIImageViewRecorder(identifier: UUID()),
        UITextFieldRecorder(identifier: UUID()),
        UITextViewRecorder(identifier: UUID()),
        UISwitchRecorder(identifier: UUID()),
        UISliderRecorder(identifier: UUID()),
        UISegmentRecorder(identifier: UUID()),
        UIStepperRecorder(identifier: UUID()),
        UINavigationBarRecorder(identifier: UUID()),
        UITabBarRecorder(identifier: UUID()),
        UIPickerViewRecorder(identifier: UUID()),
        UIDatePickerRecorder(identifier: UUID()),
        WKWebViewRecorder(identifier: UUID()),
        UIProgressViewRecorder(identifier: UUID()),
        UIActivityIndicatorRecorder(identifier: UUID()),
    ]

    if #available(iOS 18.1, tvOS 18.1, *) {
        recorders.append(iOS18HostingViewRecorder(identifier: UUID()))
    } else if #available(iOS 13, tvOS 13, *) {
        recorders.append(UIHostingViewRecorder(identifier: UUID()))
    }

    return recorders
}
#endif
