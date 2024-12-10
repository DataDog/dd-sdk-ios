//
//  AnimatableView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-26.
//

import Foundation
import SwiftUI
import UIKit

struct AnimatableView: UIViewRepresentable {
    
    private let images : [UIImage]
    private let duration: CGFloat
    private let frame: CGRect
    
    init(images: [UIImage], duration: CGFloat, frame: CGRect) {
        self.images = images
        self.duration = duration
        self.frame = frame
    }
    
    func makeUIView(context: Self.Context) -> UIView {
        
        let container = UIView(frame: frame)
        let animatedImage = UIImage.animatedImage(with: images, duration: duration)
        let animatedImageView = UIImageView(frame: frame)
        
        animatedImageView.clipsToBounds = true
        animatedImageView.autoresizesSubviews = true
        animatedImageView.contentMode = UIView.ContentMode.scaleAspectFill
        animatedImageView.image = animatedImage
        animatedImageView.animationRepeatCount = 0
        
        container.addSubview(animatedImageView)
        
        return container
    }

    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<AnimatableView>) { }
}
