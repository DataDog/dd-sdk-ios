//
//  AccesibilityView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 { YOUR NAME HERE 🏆 }
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

struct AccesibilityView: View {

    /// accessing the selected content size (user an select it in Settings in the iPhone)
    @Environment(\.dynamicTypeSize) var sizeCategory

    /// accessing the user preference for reduced motion
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// toggles used to fake some action when tapping on the buttons
    @State var seeMorePressed = false
    @State var likePressed = false
    @State var buyPressed = false
    
    let id: String = "AccesibilityView"
    
    var body: some View {
        NavigationStack{
            VStack(alignment: .leading){
                
                /// Header Level 2
                Text("A list of grocery items")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h2)
                    .padding()
                
                /// Header Level 3
                List {
                    Section(header: Text("Cans").font(.title)) {
                        Group {
                            
                            VStack(alignment: .leading) {
                                Text("Green peas")
                                Divider()
                                HStack{
                                    Button(action: {
                                        // see more action
                                        seeMorePressed.toggle()
                                    }, label: {
                                        Text("See more \(seeMorePressed ? "pressed" : "")")
                                    })
                                    .padding()
                                    .border(seeMorePressed ? .purple : .black, width: 1)
                                    Button(action: {
                                        // like action
                                        likePressed.toggle()
                                    }, label: {
                                        Text("Like \(likePressed ? "pressed" : "")")
                                    })
                                    .padding()
                                    .border(likePressed ? .purple : .black, width: 1)
                                    Button(action: {
                                        // buy action
                                        buyPressed.toggle()
                                    }, label: {
                                        Text("Buy \(buyPressed ? "pressed" : "")")
                                    })
                                    .padding()
                                    .border(buyPressed ? .purple : .black, width: 1)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("In this view you can access some actions on Green Peas")
                                .accessibilityAction(named: Text("See more")) {
                                    // see more logic
                                    seeMorePressed.toggle()
                                }
                                .accessibilityAction(named: Text("Like")) {
                                    // like logic
                                    likePressed.toggle()
                                }
                                .accessibilityAction(named: Text("Buy")) {
                                    // buy logic
                                    buyPressed.toggle()
                                }
                            }
                            .padding()
                            Text("Cat food")
                            Text("Canned tunna")
                        }
                        .font(.title2)
                    }
                    .accessibilityHeading(.h3)
                    
                    Section(header: Text("Fruits")) {
                        
                        if sizeCategory > DynamicTypeSize.medium {
                            // if the size category grows then let's just display each fruit in a separate row
                            Text("Dry fruits:")
                            Text("Nuts")
                            Text("Peanuts")
                            Text("Fresh fruits:")
                            Text("Apple")
                            Text("Mandarinen")
                            Text("Mangoes")
                        } else {
                            // if the size category is equal or less than medium, then let's add an horizontal stack to not occupy much space in the list
                            HStack {
                                Text("Dry fruits:")
                                Text("Nuts")
                                Text("Peanuts")
                            }
                            HStack {
                                Text("Fresh fruits:")
                                Text("Apple")
                                Text("Mandarinen")
                                Text("Mangoes")
                            }
                        }
                    }
                    .accessibilityHeading(.h3)
                    
                    Section(header: Text("Cheese")) {
                        Text("Fresh cheese")
                        Text("Roquefort")
                    }
                    .accessibilityHeading(.h3)
                }
                .listStyle(GroupedListStyle())
                
                /// Header level 1 by default
                .navigationTitle("Headings example")
                
            }
        }
    }
}

#Preview {
    
        AccesibilityView()
    
}
