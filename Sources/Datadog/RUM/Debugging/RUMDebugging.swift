/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

internal protocol RUMDebugging {
    func debug(applicationScope: RUMApplicationScope)
}

#if targetEnvironment(simulator)
import UIKit
import Foundation

internal struct RUMDebugInfo {
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

internal class RUMDebuggingInSimulator: RUMDebugging {
    private lazy var canvas: UIView = {
        let window = UIApplication.shared.keyWindow
        let view = RUMDebugView(frame: window?.bounds ?? .zero)
        window?.addSubview(view)
        return view
    }()

    deinit {
        let canvas = self.canvas
        DispatchQueue.main.async {
            canvas.removeFromSuperview()
        }
    }

    func debug(applicationScope: RUMApplicationScope) {
        // `RUMDebugInfo` must be created on the caller thread.
        let debugInfo = RUMDebugInfo(applicationScope: applicationScope)

        DispatchQueue.main.async {
            // `RUMDebugInfo` rendering must be called on the main thread.
            self.renderOnMainThread(rumDebugInfo: debugInfo)
        }
    }

    private func renderOnMainThread(rumDebugInfo: RUMDebugInfo) {
        canvas.subviews.forEach {
            $0.removeFromSuperview()
        }

        let viewOutlines = rumDebugInfo.views.map { RUMViewOutline(viewInfo: $0) }

        var nextOutlineFrame = canvas.bounds.inset(by: canvas.safeAreaInsets)
        var nextOutlineAlpha = CGFloat(0.75)

        viewOutlines.forEach { viewOutline in
            viewOutline.frame = nextOutlineFrame
            viewOutline.alpha = nextOutlineAlpha

            nextOutlineFrame = nextOutlineFrame.insetBy(
                dx: RUMViewOutline.Constants.lineWidth,
                dy: RUMViewOutline.Constants.lineWidth
            )
            nextOutlineAlpha *= nextOutlineAlpha
        }

        viewOutlines.forEach {
            canvas.addSubview($0)
            $0.setNeedsDisplay()
        }
    }
}

private class RUMViewOutline: RUMDebugView {
    struct Constants {
        static let activeViewColor =  #colorLiteral(red: 0.4686954021, green: 0.2687242031, blue: 0.7103499174, alpha: 1)
        static let inactiveViewColor =  #colorLiteral(red: 0.501960814, green: 0.501960814, blue: 0.501960814, alpha: 1)
        static let lineWidth: CGFloat = 15

        static let viewNameTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: Constants.lineWidth * 0.8, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        static let viewDetailsTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: Constants.lineWidth * 0.5, weight: .regular),
            .foregroundColor: UIColor.white,
        ]
    }

    private let color: UIColor
    private let label: UILabel

    init(viewInfo: RUMDebugInfo.View) {
        self.color = viewInfo.isActive ? Constants.activeViewColor : Constants.inactiveViewColor
        self.label = UILabel(frame: .zero)

        let viewName = viewInfo.uri
        let separator = " # "
        let viewDetails = (viewInfo.isActive ? "ACTIVE" : "INACTIVE")
        let labelText = "\(viewName)\(separator)\(viewDetails)"
        let labelAttributedText = NSMutableAttributedString(string: labelText)

        labelAttributedText.setAttributes(
            Constants.viewNameTextAttributes,
            range: NSRange(location: 0, length: viewName.count)
        )

        labelAttributedText.setAttributes(
            Constants.viewDetailsTextAttributes,
            range: NSRange(location: viewName.count, length: separator.count + viewDetails.count)
        )

        label.attributedText = labelAttributedText
        label.textAlignment = .left
        super.init(frame: .zero)
        addSubview(label)
    }

    override func draw(_ rect: CGRect) {
        let innerRect = rect.insetBy(dx: Constants.lineWidth * 0.5, dy: Constants.lineWidth * 0.5)
        let path = UIBezierPath(rect: innerRect)
        color.set()
        path.lineWidth = Constants.lineWidth
        path.stroke()
    }

    override func layoutSubviews() {
        label.frame = .init(
            x: bounds.minX + Constants.lineWidth,
            y: bounds.maxY - Constants.lineWidth,
            width: bounds.width - 2 * Constants.lineWidth,
            height: Constants.lineWidth
        )
    }
}

private class RUMDebugView: UIView {
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
