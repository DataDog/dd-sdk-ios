/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import QuartzCore
import SwiftUI
import UIKit
import XCTest
import DatadogInternal
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import SRHost

@available(iOS 13.0, *)
internal struct LayerSnapshotOutput {
    let layerTreeSnapshot: LayerTreeSnapshot
    let compositionTree: SRCompositionTree
    let wireframes: [SRWireframe]
    let resources: [Resource]
}

@available(iOS 13.0, *)
internal class LayerSnapshotTestCase: XCTestCase {
    @MainActor private var app: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

    // swiftlint:disable function_default_parameter_at_end
    @MainActor
    func takeLayerSnapshotFor<Content: View>(
        _ view: Content,
        with textAndInputPrivacyLevels: [TextAndInputPrivacyLevel] = [.maskSensitiveInputs],
        imagePrivacyLevel: ImagePrivacyLevel = .maskNonBundledOnly,
        waitTime: TimeInterval = 0.2,
        shouldRecord: Bool,
        folderPath: String,
        fileNamePrefix: String? = nil,
        file: StaticString = #filePath,
        function: StaticString = #function
    ) async throws {
        let viewController = UIHostingController(rootView: view)
        viewController.view.backgroundColor = .systemBackground

        try await takeLayerSnapshotFor(
            viewController,
            with: textAndInputPrivacyLevels,
            imagePrivacyLevel: imagePrivacyLevel,
            waitTime: waitTime,
            shouldRecord: shouldRecord,
            folderPath: folderPath,
            fileNamePrefix: fileNamePrefix,
            file: file,
            function: function
        )
    }

    @MainActor
    func takeLayerSnapshotFor(
        _ viewController: UIViewController,
        with textAndInputPrivacyLevels: [TextAndInputPrivacyLevel] = [.maskSensitiveInputs],
        imagePrivacyLevel: ImagePrivacyLevel = .maskNonBundledOnly,
        waitTime: TimeInterval = 0.2,
        shouldRecord: Bool,
        folderPath: String,
        fileNamePrefix: String? = nil,
        file: StaticString = #filePath,
        function: StaticString = #function
    ) async throws {
        try await show(viewController)
        await wait(seconds: waitTime)

        for textAndInputPrivacyLevel in textAndInputPrivacyLevels {
            let image = try await takeLayerSnapshot(
                textAndInputPrivacyLevel: textAndInputPrivacyLevel,
                imagePrivacyLevel: imagePrivacyLevel
            )
            let fileNameSuffix = if let fileNamePrefix {
                "-\(fileNamePrefix)-\(textAndInputPrivacyLevel)-privacy"
            } else {
                "-\(textAndInputPrivacyLevel)-privacy"
            }

            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(
                    named: folderPath,
                    fileNameSuffix: fileNameSuffix,
                    file: file,
                    function: function
                ),
                record: shouldRecord,
                simulator: .layerTree,
                file: file
            )
        }
    }
    // swiftlint:enable function_default_parameter_at_end

    @MainActor
    @discardableResult
    func show(_ viewController: UIViewController) async throws -> UIViewController {
        viewController.modalPresentationStyle = .fullScreen

        guard let presenter = app.keyWindow?.rootViewController else {
            throw LayerSnapshotTestError.missingRootViewController
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let present = {
                    presenter.present(viewController, animated: false) {
                        viewController.view.setNeedsLayout()
                        viewController.view.layoutIfNeeded()
                        continuation.resume(returning: viewController)
                    }
                }

                if presenter.presentedViewController != nil {
                    presenter.dismiss(animated: false, completion: present)
                } else {
                    present()
                }
            }
        }
    }

    @MainActor
    func takeLayerSnapshot(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskSensitiveInputs,
        imagePrivacyLevel: ImagePrivacyLevel = .maskNonBundledOnly
    ) async throws -> UIImage {
        let output = try await captureLayerSnapshot(
            textAndInputPrivacyLevel: textAndInputPrivacyLevel,
            imagePrivacyLevel: imagePrivacyLevel
        )

        guard !output.compositionTree.root.children.isEmpty else {
            XCTFail("Recorded an empty composition tree.")
            return UIImage()
        }

        guard !output.wireframes.isEmpty else {
            XCTFail("Recorded no wireframes.")
            return UIImage()
        }

        let renderedCompositionTree = renderImage(
            for: output.compositionTree,
            wireframes: output.wireframes,
            resources: output.resources
        )

        var layerTreeRoot = ""
        dump(output.layerTreeSnapshot.root, to: &layerTreeRoot)
        let layerTreeSnapshotAttachment = XCTAttachment(string: layerTreeRoot)
        layerTreeSnapshotAttachment.name = "recorded-layer-tree-root-(\(textAndInputPrivacyLevel)).txt"
        layerTreeSnapshotAttachment.lifetime = .deleteOnSuccess
        add(layerTreeSnapshotAttachment)

        let compositionTreeAttachment = XCTAttachment(
            string: renderedCompositionTree.debugInfo.dumpCompositionTreeAsJSON()
        )
        compositionTreeAttachment.name = "recorded-composition-tree-(\(textAndInputPrivacyLevel)).json"
        compositionTreeAttachment.lifetime = .deleteOnSuccess
        add(compositionTreeAttachment)

        let wireframesAttachment = XCTAttachment(
            string: renderedCompositionTree.debugInfo.dumpWireframesAsJSON()
        )
        wireframesAttachment.name = "recorded-wireframes-(\(textAndInputPrivacyLevel)).json"
        wireframesAttachment.lifetime = .deleteOnSuccess
        add(wireframesAttachment)

        guard let window = app.keyWindow else {
            throw LayerSnapshotTestError.missingKeyWindow
        }

        return createSideBySideImage(
            leftImage: renderWindowImage(for: window),
            rightImage: renderedCompositionTree.image,
            rightTitle: "Composition tree:"
        )
    }

    @MainActor
    func captureLayerSnapshot(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskSensitiveInputs,
        imagePrivacyLevel: ImagePrivacyLevel = .maskNonBundledOnly,
        timeout: TimeInterval = 30
    ) async throws -> LayerSnapshotOutput {
        guard let window = app.keyWindow else {
            throw LayerSnapshotTestError.missingKeyWindow
        }

        let context = LayerRecordingContext(
            textAndInputPrivacy: textAndInputPrivacyLevel,
            imagePrivacy: imagePrivacyLevel,
            touchPrivacy: .show,
            applicationID: "snapshot-test-application",
            sessionID: "snapshot-test-session",
            viewID: "snapshot-test-view",
            viewServerTimeOffset: 0,
            viewPath: "/snapshot-test",
            date: Date(timeIntervalSince1970: 0),
            telemetry: NOPTelemetry()
        )

        let snapshotBuilder = LayerTreeSnapshotBuilder(layerProvider: WindowLayerProvider(window: window))

        guard var layerTreeSnapshot = snapshotBuilder.takeSnapshot(context: context) else {
            throw LayerSnapshotTestError.missingLayerTreeSnapshot
        }

        guard
            let optimizedRoot = layerTreeSnapshot.root
                .resolvingPortalLayers()
                .removingOccluded()
        else {
            throw LayerSnapshotTestError.missingOptimizedRoot
        }

        layerTreeSnapshot.root = optimizedRoot

        let imageSnapshotter = ImageSnapshotter()
        let imageSnapshots = await imageSnapshotter.takeImageSnapshots(
            for: layerTreeSnapshot.root,
            changeset: CALayerChangeset(),
            timeout: timeout
        )

        let output = CompositionTreeBuilder(
            root: layerTreeSnapshot.root,
            webViewSlotIDs: layerTreeSnapshot.webViewSlotIDs,
            embeddedContentSlots: layerTreeSnapshot.embeddedContentSlots,
            imageSnapshots: imageSnapshots
        ).build()

        return LayerSnapshotOutput(
            layerTreeSnapshot: layerTreeSnapshot,
            compositionTree: output.compositionTree,
            wireframes: output.wireframes,
            resources: output.resources
        )
    }

    func wait(seconds: TimeInterval) async {
        let isCI = Bundle.main.infoDictionary?["IsRunningOnCI"] as? String == "true"
        let ciMultiplier: TimeInterval = isCI ? 5 : 1
        let nanoseconds = UInt64(seconds * ciMultiplier * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    @MainActor
    private func renderWindowImage(for window: UIWindow) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}

@available(iOS 13.0, *)
@MainActor
private final class WindowLayerProvider: LayerProvider {
    private weak var window: UIWindow?

    var rootLayer: CALayer? {
        window?.layer
    }

    init(window: UIWindow) {
        self.window = window
    }
}

private enum LayerSnapshotTestError: Error {
    case missingKeyWindow
    case missingRootViewController
    case missingLayerTreeSnapshot
    case missingOptimizedRoot
}
