//
//  MotionsAnimation.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 01.08.21.
//

import SwiftUI

struct MotionAnimationView: View, Comparable {
    
    // MARK: - Properties
    
    let id: String = "MotionAnimationView"
    
    @State private var randomShapeCount = Int.random(in: 12...26)
    @State private var isAnimating: Bool = false
    
    // MARK: Functions random
    
    func randomCoordinate(max: CGFloat) -> CGFloat {
        return CGFloat.random(in: 0...max)
    }
    
    var randomColor: Color {
        [Color.blue, Color.pink, .green].randomElement() ?? .accentColor
    }
    
    func randomSize() -> CGFloat {
        return CGFloat.random(in: 10...500)
    }
    
    func randomScale() -> CGFloat {
        return CGFloat(Double.random(in: 0.1...2.0))
    }
    
    func randomSpeed() -> Double {
        return Double.random(in: 0.025...2.0)
    }
    
    func randomDelay() -> Double {
        return Double.random(in: 0...2)
    }
    
    // MARK: - Body
    
    
    var body: some View {
        
        ScrollView {
            GeometryReader { geometry in
                ZStack {
                    
                    ForEach(0...randomShapeCount, id: \.self) { item in
                        Circle()
                            .foregroundColor(randomColor)
                            .opacity(0.15)
                            .frame(width: randomSize(),
                                   height: randomSize(), alignment: .center)
                            .scaleEffect(isAnimating ? randomScale() : 1)
                            .position(
                                x: randomCoordinate(max: geometry.size.width),
                                y: randomCoordinate(max: geometry.size.height)
                            )
                            .animation(
                                Animation.interpolatingSpring(stiffness: 0.5,
                                                              damping: 0.5)
                                .repeatForever()
                                .speed(randomSpeed())
                                .delay(randomDelay()),
                                value: isAnimating
                            )
                            .onAppear(perform: {
                                isAnimating = true
                            })
                    }
                    // end of loop
                    
                }
                // this allows the rendering to be faster and powered by metal
                .frame(height: 600)
                .drawingGroup()
                // end of z stack
                
            }
            // end of geometry
        }
        // end of scrollview
    }
}

#Preview {
    
        MotionAnimationView()
}

// MARK: - HASHABLE

extension MotionAnimationView {
    
    static func == (lhs: MotionAnimationView, rhs: MotionAnimationView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



