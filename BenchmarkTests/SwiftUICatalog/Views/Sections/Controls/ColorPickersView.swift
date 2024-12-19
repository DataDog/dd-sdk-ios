//
//  ColorPickersView.swift
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
/// Examples on how to use COLOR PICKERS in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/colorpicker
///
struct ColorPickersView: View, Comparable {
    
    let id: String = "ColorPickersView"
    
    @State private var bgColor1 =
    Color(.sRGB, red: 0.98, green: 0.9, blue: 0.2)
    @State private var bgColor2 =
    Color(.sRGB, red: 0.98, green: 0.9, blue: 0.2)
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView {
            Group {
                VStack(alignment: .leading) {
                    DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/colorpicker", name: "COLOR PICKER")
                    
                    Text("The color picker provides a color well that shows the currently selected color, and displays the larger system color picker that allows users to select a new color.")
                    GroupBox {
                        ColorPicker("Alignment Guides",
                                    selection: $bgColor1)
                        HStack{
                            Text("with opacity")
                                .fontWeight(.ultraLight)
                                .font(.title3)
                            Spacer()
                        }
                    }
                    .modifier(Divided())
                    GroupBox {
                        ColorPicker("Alignment Guides",
                                    selection: $bgColor2,
                                    supportsOpacity: false)
                        HStack{
                            Text("without opacity")
                                .fontWeight(.ultraLight)
                                .font(.title3)
                            Spacer()
                        }
                    }
                }
                ContributedByView(name: "Ali Ghayeni H",
                                  link: "https://github.com/alighayeni")
                .padding(.top, 80)
                
            }
        })
    }
}

#Preview {
    
        ColorPickersView()
    
}

// MARK: - HASHABLE

extension ColorPickersView {
    
    static func == (lhs: ColorPickersView, rhs: ColorPickersView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


