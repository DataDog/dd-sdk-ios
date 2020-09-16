/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Foundation

private struct RUMDebugInfo {
    struct View {
        let uri: String
        let isActive: Bool

        init(scope: RUMViewScope) {
            self.uri = scope.viewURI
            self.isActive = scope.isActiveView
        }
    }

    let views: [View]

    init(applicationScope: RUMApplicationScope) {
        self.views = (applicationScope.sessionScope?.viewScopes ?? [])
            .map { View(scope: $0) }
    }
}

internal class RUMDebugging {
    private lazy var canvas: UIView = {
        let view = RUMDebugView(frame: .zero)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    // MARK: - Initialization

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
        let canvas = self.canvas
        DispatchQueue.main.async {
            canvas.removeFromSuperview()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }

        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Internal

    func debug(applicationScope: RUMApplicationScope) {
        // `RUMDebugInfo` must be created on the caller thread.
        let debugInfo = RUMDebugInfo(applicationScope: applicationScope)

        DispatchQueue.main.async {
            // `RUMDebugInfo` rendering must be called on the main thread.
            self.renderOnMainThread(rumDebugInfo: debugInfo)
        }
    }

    // MARK: - Private

    private func renderOnMainThread(rumDebugInfo: RUMDebugInfo) {
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
            let someWindow = UIApplication.shared.keyWindow {
            canvas.frame.size = someWindow.bounds.size
            someWindow.addSubview(canvas)
        }
        canvas.superview?.bringSubviewToFront(canvas)
    }

    @objc
    private func updateLayout() {
        canvas.subviews.forEach { $0.setNeedsLayout() }
    }
}

internal class RUMViewOutline: RUMDebugView {
    private struct Constants {
        static let activeViewColor =  #colorLiteral(red: 0.3882352941, green: 0.1725490196, blue: 0.6509803922, alpha: 1)
        static let inactiveViewColor =  #colorLiteral(red: 0.6000000238, green: 0.6000000238, blue: 0.6000000238, alpha: 1)
        static let labelHeight: CGFloat = 16

        static let viewNameTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: Constants.labelHeight * 0.8, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        static let viewDetailsTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: Constants.labelHeight * 0.5, weight: .regular),
            .foregroundColor: UIColor.white,
        ]
    }

    private let label: UILabel
    private let stackOffset: CGFloat

    fileprivate init(viewInfo: RUMDebugInfo.View, stack: (index: Int, total: Int)) {
        self.label = UILabel(frame: .zero)
        self.stackOffset = CGFloat(stack.index) * Constants.labelHeight

        let viewName = viewInfo.uri
        let separator = " # "
        let viewDetails = (viewInfo.isActive ? "ACTIVE" : "INACTIVE")
        let labelText = "\(viewName)\(separator)\(viewDetails)"
        let labelAttributedText = NSMutableAttributedString(string: labelText)
        let labelBackgroundColor = viewInfo.isActive ? Constants.activeViewColor : Constants.inactiveViewColor

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

internal class RUMDebugView: UIView {
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
