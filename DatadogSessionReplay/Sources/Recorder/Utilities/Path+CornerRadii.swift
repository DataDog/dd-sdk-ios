/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import SwiftUI

@available(iOS 13.0, tvOS 13.0, *)
extension SwiftUI.Path {
    init(roundedRect rect: CGRect, cornerRadii: CALayerSnapshot.CornerRadii, cornerCurve: CALayerCornerCurve) {
        if cornerRadii == .zero {
            self.init(rect)
        } else if #available(iOS 16.0, tvOS 16.0, *), let rectangleCornerRadii = RectangleCornerRadii(cornerRadii: cornerRadii) {
            self.init(
                roundedRect: rect,
                cornerRadii: rectangleCornerRadii,
                style: .init(cornerCurve: cornerCurve)
            )
        } else {
            // It's OK to ignore `cornerCurve` and use the `.circular` approximation in this case,
            // since we don't know the exact curve Apple use for `.continuous`
            let rect = rect.standardized
            let cornerRadii = cornerRadii.clamped(to: rect)

            self.init { path in
                path.move(to: CGPoint(x: rect.minX + cornerRadii.topLeft.width, y: rect.minY))

                path.addLine(to: CGPoint(x: rect.maxX - cornerRadii.topRight.width, y: rect.minY))
                path.addCurve(
                    to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadii.topRight.height),
                    control1: CGPoint(
                        x: rect.maxX - cornerRadii.topRight.width + cornerRadii.topRight.width * .bezierKappa,
                        y: rect.minY
                    ),
                    control2: CGPoint(
                        x: rect.maxX,
                        y: rect.minY + cornerRadii.topRight.height - cornerRadii.topRight.height * .bezierKappa
                    )
                )

                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadii.bottomRight.height))
                path.addCurve(
                    to: CGPoint(x: rect.maxX - cornerRadii.bottomRight.width, y: rect.maxY),
                    control1: CGPoint(
                        x: rect.maxX,
                        y: rect.maxY - cornerRadii.bottomRight.height + cornerRadii.bottomRight.height * .bezierKappa
                    ),
                    control2: CGPoint(
                        x: rect.maxX - cornerRadii.bottomRight.width + cornerRadii.bottomRight.width * .bezierKappa,
                        y: rect.maxY
                    )
                )

                path.addLine(to: CGPoint(x: rect.minX + cornerRadii.bottomLeft.width, y: rect.maxY))
                path.addCurve(
                    to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadii.bottomLeft.height),
                    control1: CGPoint(
                        x: rect.minX + cornerRadii.bottomLeft.width - cornerRadii.bottomLeft.width * .bezierKappa,
                        y: rect.maxY
                    ),
                    control2: CGPoint(
                        x: rect.minX,
                        y: rect.maxY - cornerRadii.bottomLeft.height + cornerRadii.bottomLeft.height * .bezierKappa
                    )
                )

                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadii.topLeft.height))
                path.addCurve(
                    to: CGPoint(x: rect.minX + cornerRadii.topLeft.width, y: rect.minY),
                    control1: CGPoint(
                        x: rect.minX,
                        y: rect.minY + cornerRadii.topLeft.height - cornerRadii.topLeft.height * .bezierKappa
                    ),
                    control2: CGPoint(
                        x: rect.minX + cornerRadii.topLeft.width - cornerRadii.topLeft.width * .bezierKappa,
                        y: rect.minY
                    )
                )

                path.closeSubpath()
            }
        }
    }
}

extension CGFloat {
    /// A constant used to approximate a 90 degree circular arc with a cubic Bézier curve
    fileprivate static let bezierKappa: CGFloat = 0.5522847498307933
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.CornerRadii {
    fileprivate func clamped(to rect: CGRect) -> Self {
        .init(
            topLeft: .init(
                width: min(max(topLeft.width, 0), rect.width / 2),
                height: min(max(topLeft.height, 0), rect.height / 2)
            ),
            topRight: .init(
                width: min(max(topRight.width, 0), rect.width / 2),
                height: min(max(topRight.height, 0), rect.height / 2)
            ),
            bottomLeft: .init(
                width: min(max(bottomLeft.width, 0), rect.width / 2),
                height: min(max(bottomLeft.height, 0), rect.height / 2)
            ),
            bottomRight: .init(
                width: min(max(bottomRight.width, 0), rect.width / 2),
                height: min(max(bottomRight.height, 0), rect.height / 2)
            )
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension RoundedCornerStyle {
    fileprivate init(cornerCurve: CALayerCornerCurve) {
        switch cornerCurve {
        case .circular:
            self = .circular
        case .continuous:
            self = .continuous
        default:
            self = .circular
        }
    }
}

@available(iOS 16.0, tvOS 16.0, *)
extension RectangleCornerRadii {
    fileprivate init?(cornerRadii: CALayerSnapshot.CornerRadii) {
        guard
            cornerRadii.topLeft.isSquare,
            cornerRadii.topRight.isSquare,
            cornerRadii.bottomLeft.isSquare,
            cornerRadii.bottomRight.isSquare
        else {
            return nil
        }

        self.init(
            topLeading: cornerRadii.topLeft.width,
            bottomLeading: cornerRadii.bottomLeft.width,
            bottomTrailing: cornerRadii.bottomRight.width,
            topTrailing: cornerRadii.topRight.width
        )
    }
}

extension CGSize {
    fileprivate var isSquare: Bool {
        return width == height
    }
}
#endif
