//
//  CustomAnimation.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-28.
//

import Foundation
import SwiftUI

extension Animation {
    @available(iOS 17.0, tvOS 17.0, *)
    static var customAnimation: Animation { customAnimation(duration: 10.0) }

    @available(iOS 17.0, tvOS 17.0, *)
    static func customAnimation(duration: TimeInterval) -> Animation {
        Animation(MyOwnAnimation(duration: duration))
    }
}

/// Since iOS 17, we can define our own animations and use them later in the same places
/// where the apple provided animations are used
@available(iOS 17.0, tvOS 17.0, *)
struct MyOwnAnimation: CustomAnimation {
    let duration: TimeInterval

    func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V : VectorArithmetic {
        if time > duration { return nil }
        
        // this creates a psychodelics crazy animation that makes the view grow randomly at the start and beginning
        // of the animation
        if time < duration / 4 {
            return value.scaled(by: Double.random(in: 0...0.5))
        } else if time > (duration / 4) * 3 {
            return value.scaled(by: Double.random(in: 0...1))
        } else {
            return value.scaled(by: time/duration)
        }
    }
}
