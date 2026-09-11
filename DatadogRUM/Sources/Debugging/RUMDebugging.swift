/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif
import DatadogInternal

#if !os(watchOS)
private struct RUMDebugInfo {
    struct View {
        let name: String
        let isActive: Bool

        init(scope: RUMViewScope) {
            self.name = scope.viewName
            self.isActive = scope.isActiveView
        }
    }

    let views: [View]

    init(applicationScope: RUMApplicationScope) {
        self.views = (applicationScope.activeSession?.viewScopes ?? [])
            .map { View(scope: $0) }
    }
}

fileprivate enum RUMDebuggingConstants {
    static let activeViewColor = #colorLiteral(red: 0.3882352941, green: 0.1725490196, blue: 0.6509803922, alpha: 1)
    static let inactiveViewColor = #colorLiteral(red: 0.6000000238, green: 0.6000000238, blue: 0.6000000238, alpha: 1)
}
#endif

#if canImport(UIKit)
internal class RUMDebugging {
    #if !os(watchOS)
    /// An overlay view rendered on top of the app content. It is created lazily on first draw.
    private var canvas: DDView? = nil
    #endif

    // MARK: - Initialization

    #if os(iOS)
    init() {
        DispatchQueue.main.async {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }

        NotificationCenter.default
            .addObserver(
                self,
                selector: #selector(RUMDebugging.updateLayout),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
        )
    }

    deinit {
        DispatchQueue.main.async { [weak canvas] in
            canvas?.removeFromSuperview()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }

        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    #else
    init() { }

    deinit {
        #if !os(watchOS)
        DispatchQueue.main.async { [weak canvas] in
            canvas?.removeFromSuperview()
        }
        #endif
    }
    #endif

    // MARK: - Internal

    func debug(applicationScope: RUMApplicationScope) {
        #if !os(watchOS)
        // `RUMDebugInfo` must be created on the caller thread.
        let debugInfo = RUMDebugInfo(applicationScope: applicationScope)

        DispatchQueue.main.async {
            // `RUMDebugInfo` rendering must be called on the main thread.
            self.renderOnMainThread(rumDebugInfo: debugInfo)
        }
        #endif
    }

    // MARK: - Private

    #if !os(watchOS)
    private func renderOnMainThread(rumDebugInfo: RUMDebugInfo) {
        if canvas == nil {
            canvas = RUMDebugView(frame: .zero)
            canvas?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        guard let canvas = canvas else {
            return
        }

        canvas.subviews.forEach { view in
            view.removeFromSuperview()
        }

        let viewOutlines: [RUMViewOutline] = zip(rumDebugInfo.views, 0..<rumDebugInfo.views.count)
            .map { viewInfo, stackIndex in
                RUMViewOutline(
                    viewInfo: viewInfo,
                    stack: (index: stackIndex, total: rumDebugInfo.views.count)
                )
            }

        viewOutlines.forEach { view in
            view.frame = canvas.frame
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            canvas.addSubview(view)
        }
        if canvas.superview == nil,
           let someWindow = DDApplication.dd.managedShared?.windows.first(where: { $0.isKeyWindow }) {
            canvas.frame.size = someWindow.bounds.size
            someWindow.addSubview(canvas)
        }
        canvas.superview?.bringSubviewToFront(canvas)
    }

    @objc
    private func updateLayout() {
        canvas?.subviews.forEach { $0.setNeedsLayout() }
    }
    #endif
}
#endif

#if !os(watchOS) && !os(macOS)
internal class RUMViewOutline: RUMDebugView {
    private struct Constants {
        static let labelHeight: CGFloat = 16

        static let viewNameTextAttributes: [NSAttributedString.Key: Any] = [
            .font: DDFont.monospacedDigitSystemFont(ofSize: Constants.labelHeight * 0.8, weight: .semibold),
            .foregroundColor: DDColor.white,
        ]
        static let viewDetailsTextAttributes: [NSAttributedString.Key: Any] = [
            .font: DDFont.monospacedDigitSystemFont(ofSize: Constants.labelHeight * 0.5, weight: .regular),
            .foregroundColor: DDColor.white,
        ]
    }

    private let label: DDLabel
    private let stackOffset: CGFloat

    fileprivate init(viewInfo: RUMDebugInfo.View, stack: (index: Int, total: Int)) {
        self.label = DDLabel(frame: .zero)
        self.stackOffset = CGFloat(stack.index) * Constants.labelHeight

        let viewName = viewInfo.name
        let separator = " # "
        let viewDetails = (viewInfo.isActive ? "ACTIVE" : "INACTIVE")
        let labelText = "\(viewName)\(separator)\(viewDetails)"
        let labelAttributedText = NSMutableAttributedString(string: labelText)
        let labelBackgroundColor = viewInfo.isActive ? RUMDebuggingConstants.activeViewColor : RUMDebuggingConstants.inactiveViewColor

        labelAttributedText.setAttributes(
            Constants.viewNameTextAttributes,
            range: NSRange(location: 0, length: viewName.count)
        )

        labelAttributedText.setAttributes(
            Constants.viewDetailsTextAttributes,
            range: NSRange(location: viewName.count, length: separator.count + viewDetails.count)
        )

        label.attributedText = labelAttributedText
        label.textAlignment = .center
        label.backgroundColor = labelBackgroundColor
        label.alpha = CGFloat(pow(0.75, Double(stack.total - stack.index)))

        super.init(frame: .zero)

        addSubview(label)
    }

    override func layoutSubviews() {
        let safeAreaBounds = bounds.inset(by: safeAreaInsets)
        label.frame = .init(
            x: bounds.minX,
            y: safeAreaBounds.maxY - stackOffset - Constants.labelHeight,
            width: bounds.width,
            height: Constants.labelHeight
        )
    }
}

internal class RUMDebugView: DDView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif

#if os(macOS)
internal class RUMDebuggingWindow: NSPanel { }

internal class RUMDebugging {
    @MainActor var debuggingViewManager: RUMDebuggingViewManager?

    init() {
        DispatchQueue.main.async {
            self.debuggingViewManager = RUMDebuggingViewManager()
        }
    }

    func debug(applicationScope: RUMApplicationScope) {
        // `RUMDebugInfo` must be created on the caller thread.
        let debugInfo = RUMDebugInfo(applicationScope: applicationScope)

        DispatchQueue.main.async {
            // `RUMDebugInfo` rendering must be called on the main thread.
            self.debuggingViewManager?.setDebugInfo(debugInfo: debugInfo)
        }
    }
}

@MainActor
internal class RUMDebuggingViewManager {
    private let debugWindow: RUMDebuggingWindow
    private let debugViewController = RUMDebuggingViewController()

    init() {
        debugWindow = RUMDebuggingWindow(contentViewController: debugViewController)
        debugWindow.styleMask = [.titled, .miniaturizable, .utilityWindow, .resizable]
        debugWindow.becomesKeyOnlyIfNeeded = true
        debugWindow.isFloatingPanel = true
        debugWindow.title = "RUM View Scopes"
        debugWindow.setContentSize(.init(width: 450, height: 150))
        debugWindow.orderFront(nil)
    }

    deinit {
        if Thread.isMainThread {
            debugWindow.close()
        } else {
            let window = debugWindow

            DispatchQueue.main.async {
                window.close()
            }
        }
    }

    fileprivate func setDebugInfo(debugInfo: RUMDebugInfo) {
        debugViewController.setDebugInfo(debugInfo: debugInfo)
    }
}

internal class RUMDebuggingViewController: NSViewController {
    private let stackView = NSStackView()

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = NSScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView = FlippedClipView()
        view.contentView.drawsBackground = false
        view.drawsBackground = false

        stackView.orientation = .vertical
        stackView.spacing = 0
        view.documentView = stackView
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.contentView.topAnchor),
            view.contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])

        self.view = view
    }

    fileprivate func setDebugInfo(debugInfo: RUMDebugInfo) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeView(view)
        }

        debugInfo.views.forEach { view in
            stackView.addArrangedSubview(labelFor(view))
        }

        stackView.arrangedSubviews.forEach { subview in
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
            ])
        }
    }

    private func labelFor(_ view: RUMDebugInfo.View) -> NSView {
        let wrapperView = NSView()
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
        wrapperView.wantsLayer = true
        wrapperView.layer?.backgroundColor = view.isActive ? RUMDebuggingConstants.activeViewColor.cgColor : RUMDebuggingConstants.inactiveViewColor.cgColor

        let activeLabel = NSTextField(labelWithString: view.isActive ? "ACTIVE" : "INACTIVE")
        activeLabel.translatesAutoresizingMaskIntoConstraints = false
        activeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        activeLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        activeLabel.setContentHuggingPriority(.required, for: .horizontal)
        activeLabel.setContentHuggingPriority(.required, for: .vertical)
        activeLabel.textColor = view.isActive ? RUMDebuggingConstants.activeViewColor : RUMDebuggingConstants.inactiveViewColor
        activeLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        let activeLabelWrapper = NSView()
        activeLabelWrapper.translatesAutoresizingMaskIntoConstraints = false
        activeLabelWrapper.wantsLayer = true
        activeLabelWrapper.layer?.backgroundColor = NSColor.white.cgColor
        activeLabelWrapper.layer?.cornerRadius = 4
        activeLabelWrapper.layer?.cornerCurve = .continuous

        activeLabelWrapper.addSubview(activeLabel)

        let textField = NSTextField(labelWithString: view.name)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.textColor = .white

        wrapperView.addSubview(textField)
        wrapperView.addSubview(activeLabelWrapper)

        NSLayoutConstraint.activate([
            activeLabel.leadingAnchor.constraint(equalTo: activeLabelWrapper.leadingAnchor, constant: 4),
            activeLabel.trailingAnchor.constraint(equalTo: activeLabelWrapper.trailingAnchor, constant: -4),
            activeLabel.topAnchor.constraint(equalTo: activeLabelWrapper.topAnchor, constant: 2),
            activeLabel.bottomAnchor.constraint(equalTo: activeLabelWrapper.bottomAnchor, constant: -2),

            textField.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 20),
            textField.topAnchor.constraint(equalTo: wrapperView.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor, constant: -8),

            activeLabelWrapper.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            activeLabelWrapper.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor, constant: -20),
            activeLabel.firstBaselineAnchor.constraint(equalTo: textField.firstBaselineAnchor)
        ])

        return wrapperView
    }
}

fileprivate class FlippedClipView: NSClipView {
    override var isFlipped: Bool {
        true
    }
}
#endif
