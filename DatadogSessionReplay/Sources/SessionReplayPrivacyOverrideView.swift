/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import SwiftUI
import DatadogInternal

@available(iOS 16, *)
public struct SessionReplayPrivacyOverrideView<Content: View>: View {
	private let isActive: Bool
	private let textAndInputPrivacy: TextAndInputPrivacyLevel?
	private let imagePrivacy: ImagePrivacyLevel?
	private let touchPrivacy: TouchPrivacyLevel?
	private let hide: Bool?
	private let core: DatadogCoreProtocol
	private let content: Content

	public init(
		isActive: Bool = true,
		textAndInputPrivacy: TextAndInputPrivacyLevel? = nil,
		imagePrivacy: ImagePrivacyLevel? = nil,
		touchPrivacy: TouchPrivacyLevel? = nil,
		hide: Bool? = nil,
		core: DatadogCoreProtocol = CoreRegistry.default,
		@ViewBuilder content: () -> Content
	) {
		self.isActive = isActive
		self.textAndInputPrivacy = textAndInputPrivacy
		self.imagePrivacy = imagePrivacy
		self.touchPrivacy = touchPrivacy
		self.hide = hide
		self.core = core
		self.content = content()
	}

	public var body: some View {
		if isActive, isSessionReplayEnabled || isRunningForPreviews {
			HostingControllerWrapper(sizingOptions: .intrinsicContentSize, content: content) { view, _ in
				// Forward privacy overrides to the container `UIView`
				view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = textAndInputPrivacy
				view.dd.sessionReplayPrivacyOverrides.imagePrivacy = imagePrivacy
				view.dd.sessionReplayPrivacyOverrides.touchPrivacy = touchPrivacy
				view.dd.sessionReplayPrivacyOverrides.hide = hide
			}
		} else {
			content
		}
	}

	private var isSessionReplayEnabled: Bool {
		core.get(feature: SessionReplayFeature.self) != nil
	}

	private var isRunningForPreviews: Bool {
		ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
	}
}

@available(iOS 16, *)
private struct HostingControllerWrapper<Content: View>: UIViewControllerRepresentable {
	let sizingOptions: UIHostingControllerSizingOptions
	let update: (_ view: UIView, _ context: Context) -> Void
	let content: Content

	init(
		sizingOptions: UIHostingControllerSizingOptions,
		content: Content,
		update: @escaping (_ view: UIView, _ context: Context) -> Void,
	) {
		self.sizingOptions = sizingOptions
		self.content = content
		self.update = update
	}

	func makeUIViewController(context: Context) -> UIHostingController<Content> {
		let hostingController = UIHostingController(rootView: content)
		hostingController.sizingOptions = sizingOptions

		hostingController.view.backgroundColor = .clear
		hostingController.view.clipsToBounds = false

		return hostingController
	}

	func updateUIViewController(_ hostingController: UIHostingController<Content>, context: Context) {
		hostingController.rootView = content
		update(hostingController.view, context)
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context) -> CGSize? {
		let proposedSize = proposal.replacingUnspecifiedDimensions(by: CGSize(width: CGFloat.infinity, height: .infinity))
		return uiViewController.sizeThatFits(in: proposedSize)
	}
}

#endif
