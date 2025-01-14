//
//  SlidersView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Barbara M. Rodeker
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

import SwiftUI

///
/// Examples on how to use SLIDERS in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/slider
///
struct SlidersView: View, Comparable {
    
    // MARK: - Properties
    
    
    let id: String = "SlidersView"
    
    @State private var grams1 = 15.0
    @State private var grams2 = 15.0
    @State private var grams3 = 15.0
    @State private var isEditing1 = false
    @State private var isEditing2 = false
    @State private var isEditing3 = false
    
    // MARK: - Body
    
    
    var body: some View {
        
        PageContainer(content:
                        
                        Group {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/slider", name: "SLIDER")
            
            VStack(alignment: .leading) {
                sliderGrams
                    .modifier(Divided())
                sliderWithVoiceOver
            }
            
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            
        })
        // end of Page container
    }
    
    private var sliderGrams: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text( "Slider with continued values")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("A slider can be configured with a range of values through which continued numbers can be selected. In this example there is a selection of grams for some tasty receipt.")
                    .fontWeight(.light)
                    .font(.title2)
                Slider(
                    value: $grams1,
                    in: 0...1000,
                    onEditingChanged: { editing in
                        isEditing1 = editing
                    }
                )
                Text("\(grams1)")
                    .foregroundColor(isEditing1 ? .blue : .black)
            }
        }
        
    }
    
    private var sliderSteps: some View {
        VStack(alignment: .leading) {
            Text("Slider with steps")
                .fontWeight(.heavy)
                .font(.title)
            Text("A slider can also be configured with a step value, that will make the choose values jump depending on the size of the step, for example here from 20 to 20 more.")
                .fontWeight(.light)
                .font(.title2)
        }
        
    }
    
    private var sliderWithVoiceOver: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text( "Slider with VoiceOver Label & min / max values")
                    .fontWeight(.heavy)
                Text("A slider can also be contained between a minimum and a maximum value. Here a label is also added to the slider, whose text will be spoken in VoiceOver to improve accessibility")
                    .fontWeight(.light)
                    .font(.title2)
                VStack {
                    Slider(value: $grams3,
                           in: 0...1000,
                           onEditingChanged: { editing in
                        isEditing3 = editing
                    },
                           minimumValueLabel: Label(
                            title: { Text("50") },
                            icon: { Image(systemName: "circle") }
                           ),
                           maximumValueLabel: Label(
                            title: { Text("900") },
                            icon: { Image(systemName: "circle") }
                            
                           ),
                           label: {
                        Text("This is a slider for grams")
                    })
                }
            }
        }
    }
    
    private var sliderGrams2: some View {
        Group {
            VStack {
                Slider(
                    value: $grams2,
                    in: 0...1000,
                    step: 20,
                    onEditingChanged: { editing in
                        isEditing2 = editing
                    }
                )
                .padding(30)
                Text("\(grams2)")
                    .foregroundColor(isEditing2 ? .blue : .black)
            }
        }
    }
    
}

#Preview {
    
        SlidersView()
    
}

// MARK: - HASHABLE

extension SlidersView {
    
    static func == (lhs: SlidersView, rhs: SlidersView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



