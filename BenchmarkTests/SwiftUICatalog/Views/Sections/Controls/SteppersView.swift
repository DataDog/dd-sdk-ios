//
//  SteppersView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Ali Ghayeni H
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
/// Examples on how to use STEPPERs in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/stepper
///
struct SteppersView: View, Comparable {
    
    //MARK: - Variables
    
    let id: String = "SteppersView"
    
    @State private var firstStepperValue = 0
    @State private var SecondStepperValue = 0
    
    private let colors: [Color] = [.orange, .red, .gray, .blue,
                                   .green, .purple, .pink]
    // Step Size
    private let step = 5
    // Total range
    private let range = 1...50
    
    //MARK: - Functions
    
    /// Increment 1 Step
    private func incrementStep() {
        firstStepperValue += 1
        if firstStepperValue >= colors.count { firstStepperValue = 0 }
    }
    
    /// Decrement 1 step
    private func decrementStep() {
        firstStepperValue -= 1
        if firstStepperValue < 0 { firstStepperValue = colors.count - 1 }
    }
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/stepper", name: "STEPPER")
            plainStepper
                .modifier(Divided())
            customStepper
                .modifier(Divided())
            
            ContributedByView(name: "Ali Ghayeni H",
                              link: "https://github.com/alighayeni")
            .padding(.top, 80)
            
        })
        // end of page container
        
    }
    
    private var customStepper: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Stepper View + custom step")
                    .fontWeight(.heavy)
                    .font(.title)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityHint("What you heard was the title of the view")
                Text("The following example shows a stepper that displays the effect of incrementing or decrementing a value with the step size of step with the bounds defined by range:")
                    .fontWeight(.light)
                    .font(.title2)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityHint("What you heard was the description of the example presented")
                Stepper(value: $SecondStepperValue,
                        in: range,
                        step: step) {
                    Text("Current: \(SecondStepperValue) in \(range.description) " +
                         "stepping by \(step)")
                    .accessibilityAddTraits(.isSummaryElement)
                }
                        .accessibilityAddTraits(.allowsDirectInteraction)
                        .padding(10)
            }
        }
        .accessibilityIdentifier("steppers.custom.stepper")
        .accessibilityHint("In this view you can experience how to define custom steps")
        
    }
    
    private var plainStepper: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Stepper View")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("Use a stepper control when you want the user to have granular control while incrementing or decrementing a value. ")
                    .fontWeight(.light)
                    .font(.title2)
                Stepper("Position: \(firstStepperValue) \nColor: \(colors[firstStepperValue].description)"
                        , onIncrement: {
                    incrementStep()
                }, onDecrement: {
                    decrementStep()
                })
            }
        }
        
    }
}

#Preview {
    
        SteppersView()
    
}

// MARK: - HASHABLE

extension SteppersView {
    
    static func == (lhs: SteppersView, rhs: SteppersView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


