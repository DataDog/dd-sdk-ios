//
//  AnimationsView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Barbara Rodeker
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//

import SwiftUI

///
/// Examples on how to use  ANIMATIONS  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/animation
/// https://developer.apple.com/documentation/swiftui/withanimation(_:_:)
/// https://developer.apple.com/documentation/swiftui/animatablepair
/// https://developer.apple.com/documentation/swiftui/emptyanimatabledata
/// https://developer.apple.com/documentation/swiftui/anytransition
///
///

struct AnimationsView: View, Comparable {
    
    // MARK: - Properties
    
    let id: String = "AnimationsView"
    
    @State private var animate1 = false
    @State private var animate2 = false
    @State private var animate3 = false
    
    
    // MARK: - Body
    
    
    var body: some View {
        
        NavigationStack {
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/animation")
                .padding(.trailing)
            List {
                Link(destination:                         RobbieWithPulseView(),
                     label: "Pulse animation",
                     textColor: .black)
                .listRowBackground(Color.white)
                Link(destination:                         MyCustomAnimationView(),
                     label: "Custom animations",
                     textColor: .black)
                .listRowBackground(Color.white)
                Link(destination:                         SpringAnimationView(),
                     label: "Springs animations",
                     textColor: .black)
                .listRowBackground(Color.white)
                Link(destination:                         IconsAnimationsView(),
                     label: "Icons animations",
                     textColor: .black)
                .listRowBackground(Color.white)
                Link(destination:                         TimingCurvesView(),
                     label: "Timing curves in animations",
                     textColor: .black)
                .listRowBackground(Color.white)
                Link(destination: PropertiesAnimationsView(),
                     label: "Properties animations",
                     textColor: .black)
                .listRowBackground(Color.white)
                Link(destination: TransitionsAnimationsView(),
                     label: "Transitions animations",
                     textColor: .black)
                .listRowBackground(Color.white)
                Link(destination: VStack(alignment: .leading) {
                    Group {
                        Text("Circles in motion animation")
                            .fontWeight(.heavy)
                            .font(.title)
                            .padding(.top)
                        Text("A custom complex animation using geometry reader to create shapes and make them move and scale around the screen")
                            .fontWeight(.light)
                            .font(.title2)
                        MotionAnimationView()
                    }
                    .padding(.horizontal)
                } ,
                     label: "Moving circles animations",
                     textColor: .black)
                .listRowBackground(Color.white)
            }
            .navigationTitle("Animations")
        }
    }
}

// MARK: - previews

#Preview {
    
        AnimationsView()
            
    
}

// MARK: - extensions of animations


extension Animation {
    static func ripple(index: Int) -> Animation {
        Animation.spring(dampingFraction: 0.5)
            .speed(2)
            .delay(0.03 * Double(index))
    }
}

// MARK: - custom transitions

extension AnyTransition {
    static var moveAndFade: AnyTransition {
        let insertion = AnyTransition.move(edge: .leading)
            .combined(with: .opacity)
        let removal = AnyTransition.scale
            .combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

// MARK: - HASHABLE

extension AnimationsView {
    
    static func == (lhs: AnimationsView, rhs: AnimationsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}

extension TransitionsAnimationsView {
    
    static func == (lhs: TransitionsAnimationsView, rhs: TransitionsAnimationsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}

extension PropertiesAnimationsView {
    
    static func == (lhs: PropertiesAnimationsView, rhs: PropertiesAnimationsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


