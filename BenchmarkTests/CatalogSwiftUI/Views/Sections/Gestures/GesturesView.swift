//
//  GesturesView.swift
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
/// Examples on how to use  GESTURES  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/adding-interactivity-with-gestures
/// https://developer.apple.com/documentation/swiftui/composing-swiftui-gestures
///
///

struct GesturesView: View, Comparable {
    
    let id: String = "GesturesView"
    
    @GestureState private var isDetectingLongPress = false
    @State private var totalNumberOfTaps = 0
    @State private var customText = "No Tap Detected yet!"
    
    var body: some View {
        
        //MARK: Gestures
        let tap = TapGesture()
            .onEnded{ _ in
                self.customText = "Tap Detected!"
                print("View tapped!")
            }
        
        let lognPress = LongPressGesture(minimumDuration: 2)
        /**
         - Update Transient UI State
         To update a view as a gesture changes, add a GestureState property to your view and update it in the updating(_:body:) callback. SwiftUI invokes the updating callback as soon as it recognizes the gesture and whenever the value of the gesture changes. For example, SwiftUI invokes the updating callback as soon as a magnification gesture begins and then again whenever the magnification value changes. SwiftUI doesn’t invoke the updating callback when the user ends or cancels a gesture. Instead, the gesture state property automatically resets its state back to its initial value.
         */
            .updating($isDetectingLongPress) { currentState, gestureState, transaction in
                gestureState = currentState
            }
        /**
         - Update Permanent State During a Gesture
         To track changes to a gesture that shouldn’t reset once the gesture ends, use the onChanged(_:) callback. For example, to count the number of times your app recognizes a long press, add an onChanged(_:) callback and increment a counter.
         */
            .onChanged {_ in
                self.totalNumberOfTaps += 1
            }
        /**
         - Update Permanent State When a Gesture Ends
         To recognize when a gesture successfully completes and to retrieve the gesture’s final value, use the onEnded(_:) function to update your app’s state in the callback. SwiftUI only invokes the onEnded(_:) callback when the gesture succeeds. For example, during a LongPressGesture if the user stops touching the view before minimumDuration seconds have elapsed or moves their finger more than maximumDistance points SwiftUI does not invoke the onEnded(_:) callback.
         */
            .onEnded { _ in
                self.customText = "Long press Detected!"
                print("View Pressed for two seconds!")
            }
        
        ScrollView {
            VStack(alignment: .leading) {
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/adding-interactivity-with-gestures", name: "GESTURE INTERACTIONS")
                
                intro
                
                Spacer(minLength: 30)
                
                // MARK: - Circle shape + Gestures
                Group {
                    Label(
                        title: { Text("Circle Shape + Gesture") },
                        icon: {  }
                    )
                    HStack{
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 100, height: 100, alignment: .center)
                        /**
                         Add Gesture Modifiers to a View
                         Each gesture you add applies to a specific view in the view hierarchy. To recognize a gesture event on a particular view, create and configure the gesture, and then use the gesture(_:including:) modifier:
                         */
                            .gesture(tap)
                        
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 100, height: 100, alignment: .center)
                            .gesture(lognPress)
                    }
                }
                Spacer(minLength: 30)
                
            }
            
            ContributedByView(name: "Ali Ghayeni H",
                              link: "https://github.com/alighayeni")
            .padding(.top, 80)
            
        }
        .padding(.horizontal)
        
    }
    
    private var intro: some View {
        Group {
            Text("Gesture modifiers handle all of the logic needed to process user-input events such as touches, and recognize when those events match a known gesture pattern, such as a long press or rotation. When recognizing a pattern, SwiftUI runs a callback you use to update the state of a view or perform an action.")
            Spacer()
            Label(
                title: { Text(customText).padding(.vertical) },
                icon: {  }
            )
            Spacer()
            Label(
                title: { Text("** Try Tap on objects on the left side. Try Long press on objects on the right side.")
                        .font(.system(size: 14, weight: .light))
                },
                icon: {  }
            )
        }
    }
    
}

#Preview {
    
        GesturesView()
    
}

// MARK: - HASHABLE

extension GesturesView {
    
    static func == (lhs: GesturesView, rhs: GesturesView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


