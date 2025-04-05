/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
public class RUMWidgetHostingController: UIHostingController<RUMWidgetView> {
    private var isExpanded: Bool = false

    private let padding: CGFloat = 10
    private let topPadding: CGFloat = 80
    private var bottomPadding: CGFloat = 0

    public init() {
        let view = RUMWidgetView()
        super.init(rootView: view)
        self.view.backgroundColor = .clear
        self.rootView.onExpandView = { [weak self] isExpanded in

            self?.isExpanded = isExpanded
            self?.updateFrame(isExpanded: isExpanded)
        }
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setup(superView: UIView, bottomPadding: CGFloat = 0) {
        self.bottomPadding = bottomPadding

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        self.view.addGestureRecognizer(panGesture)

        superView.addSubview(self.view)
        updateFrame(isExpanded: false, isAnimated: false)
    }

    func updateFrame(isExpanded: Bool, isAnimated: Bool = true) {
        let frame = isExpanded
        ? CGRect(x: 0, y: topPadding, width: UIScreen.main.bounds.width, height: 180)
        : CGRect(
            x: UIScreen.main.bounds.width - FloatingButtonView.size.width - padding,
            y: UIScreen.main.bounds.height - FloatingButtonView.size.height - padding - bottomPadding,
            width: FloatingButtonView.size.width,
            height: FloatingButtonView.size.height
        )

        UIView.animate(withDuration: isAnimated ? 1/3 : 0, delay: 0, options: .curveEaseInOut) {
            self.view.frame = frame
        }
    }

    @objc func handleDrag(_ gesture: UIPanGestureRecognizer) {
        guard let draggedView = gesture.view else { return }

        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            draggedView.center = CGPoint(
                x: draggedView.center.x + translation.x,
                y: draggedView.center.y + translation.y
            )
            gesture.setTranslation(.zero, in: view)
        case .ended, .cancelled:

            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height

            let x = draggedView.center.x < screenWidth / 2
            ? padding
            : screenWidth - padding - FloatingButtonView.size.width

            // Clamp Y within top/bottom bounds
            let minY = self.isExpanded ? 240.0 : 165
            let maxY = self.isExpanded ? topPadding : 105
            let clampedY = min(
                max(padding + maxY, draggedView.frame.origin.y),
                screenHeight - padding - minY
            )

            UIView.animate(withDuration: 1/4, delay: 0, options: .curveEaseOut) {
                let frame = self.isExpanded
                ? CGRect(x: 0, y: clampedY, width: UIScreen.main.bounds.width, height: 180)
                : CGRect(x: x, y: clampedY, width: FloatingButtonView.size.width, height: FloatingButtonView.size.height)

                draggedView.frame = frame
                gesture.setTranslation(.zero, in: draggedView)
            }
        default:
            break
        }
    }
}
