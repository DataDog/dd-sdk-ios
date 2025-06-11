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
	private let content: () -> Content

	public init(
		isActive: Bool = true,
		textAndInputPrivacy: TextAndInputPrivacyLevel? = nil,
		imagePrivacy: ImagePrivacyLevel? = nil,
		touchPrivacy: TouchPrivacyLevel? = nil,
		hide: Bool? = nil,
		core: DatadogCoreProtocol = CoreRegistry.default,
		@ViewBuilder content: @escaping () -> Content
	) {
		self.isActive = isActive
		self.textAndInputPrivacy = textAndInputPrivacy
		self.imagePrivacy = imagePrivacy
		self.touchPrivacy = touchPrivacy
		self.hide = hide
		self.core = core
		self.content = content
	}

	public var body: some View {
		if isActive, isSessionReplayEnabled || isRunningForPreviews {
			SessionReplayPrivacyOverrideHost(
				textAndInputPrivacy: textAndInputPrivacy,
				imagePrivacy: imagePrivacy,
				touchPrivacy: touchPrivacy,
				hide: hide,
				content: content
			)
		} else {
			content()
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
private struct SessionReplayPrivacyOverrideHost<Content: View>: UIViewControllerRepresentable {
	typealias HostedContent = EnvironmentView<Content>

	let textAndInputPrivacy: TextAndInputPrivacyLevel?
	let imagePrivacy: ImagePrivacyLevel?
	let touchPrivacy: TouchPrivacyLevel?
	let hide: Bool?
	let content: () -> Content

	func makeUIViewController(context: Context) -> UIHostingController<HostedContent> {
		// We need to forward the environment in iOS 16 / 17
		let hostingController = UIHostingController(rootView: EnvironmentView(context.environment, content: content))
		hostingController.sizingOptions = .intrinsicContentSize

		hostingController.view.backgroundColor = .clear
		hostingController.view.clipsToBounds = false

		return hostingController
	}

	func updateUIViewController(_ hostingController: UIHostingController<HostedContent>, context: Context) {
		// We need to forward the environment in iOS 16 / 17
		hostingController.rootView = EnvironmentView(context.environment, content: content)

		// Forward privacy overrides to the host `UIView`
		hostingController.view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = textAndInputPrivacy
		hostingController.view.dd.sessionReplayPrivacyOverrides.imagePrivacy = imagePrivacy
		hostingController.view.dd.sessionReplayPrivacyOverrides.touchPrivacy = touchPrivacy
		hostingController.view.dd.sessionReplayPrivacyOverrides.hide = hide
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<HostedContent>, context: Context) -> CGSize? {
		let proposedSize = proposal.replacingUnspecifiedDimensions(by: CGSize(width: CGFloat.infinity, height: .infinity))
		return uiViewController.sizeThatFits(in: proposedSize)
	}
}

@available(iOS 16, *)
private struct EnvironmentView<Content: View>: View {
	private let environment: EnvironmentValues
	private let content: () -> Content

	init(_ environment: EnvironmentValues, content: @escaping () -> Content) {
		self.environment = environment
		self.content = content
	}

	var body: some View {
		if #available(iOS 18, *) {
			// No need to forward the environment
			content()
		} else {
			content().environment(\.self, environment)
		}
	}
}

#endif
