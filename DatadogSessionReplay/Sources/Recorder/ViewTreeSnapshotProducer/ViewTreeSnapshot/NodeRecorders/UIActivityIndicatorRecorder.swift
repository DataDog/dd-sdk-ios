/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UIActivityIndicatorRecorder: NodeRecorder {
    let identifier = UUID()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let activityIndicator = view as? UIActivityIndicatorView else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        guard activityIndicator.isAnimating || !activityIndicator.hidesWhenStopped else {
            return InvisibleElement.constant
        }

        let builder = UIActivityIndicatorWireframesBuilder(
            attributes: attributes,
            wireframeID: context.ids.nodeID(view: activityIndicator, nodeRecorder: self),
            backgroundColor: activityIndicator.backgroundColor?.cgColor
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        let allNodes = [node] + recordSubtree(of: activityIndicator, in: context)
        return SpecificElement(subtreeStrategy: .ignore, nodes: allNodes)
    }

    private func recordSubtree(of activityIndicator: UIActivityIndicatorView, in context: ViewTreeRecordingContext) -> [Node] {
        let subtreeViewRecorder = ViewTreeRecorder(
            nodeRecorders: [
                UIImageViewRecorder(
                    shouldRecordImagePredicate: { imageView in

                        print("animationImages:", imageView.animationImages?.count)
                        print("animationDuration:", imageView.animationDuration)

                        /*if let animationImages = imageView.animationImages {
                            for animationImage in animationImages {
                                print("animationImage:", animationImage)
                                if animationImage.pngData() != nil {
                                    print("PNG")
                                } else if animationImage.jpegData(compressionQuality: 1.0) != nil {
                                    print("JPEG")
                                }
                            }
                        }*/

                        print("animationKeys():", imageView.layer.animationKeys()?.count)

                        if let animationKeys = imageView.layer.animationKeys() {
                            for animationKey in animationKeys {
                                print("animationKey:", animationKey)
                                if let animation = imageView.layer.animation(forKey: animationKey) {
                                    print("animation:", animation)
                                    print("duration: \(animation.duration)")
                                    print("repeat count: \(animation.repeatCount)")
                                }
                            }
                        }

                        return imageView.image == nil ? false : true
                    }
                )
            ]
        )

        return subtreeViewRecorder.record(activityIndicator, in: context)
    }
}

internal struct UIActivityIndicatorWireframesBuilder: NodeWireframesBuilder {
    var wireframeRect: CGRect { attributes.frame }
    let attributes: ViewAttributes

    let wireframeID: WireframeID
    let backgroundColor: CGColor?

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createShapeWireframe(
                id: wireframeID,
                frame: wireframeRect,
                backgroundColor: backgroundColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
