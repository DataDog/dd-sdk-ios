//
//  EffectsModifiersView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Barbara Martina Rodeker
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
/// Examples on how to use  Effects Modifiers  in SwiftUI
/// To see all available modifiers select a view in anypreview and inspect the "Effects Modifiers" section
///

struct EffectsModifiersView: View, Comparable {
    
    let id: String = "EffectsModifiersView"
    
    var body: some View {
        
        VStack(alignment: .leading) {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/view/rotationeffect(_:anchor:)")
            
            Text("There are different effects that are provided out of the box and can be applied to any view, such as for example applying a degree of rotation, a shadow, a blurring effect.")
                .fontWeight(.light)
                .font(.title2)
            List {
                rotation
                masking
                grayScale
                
                // todo: keep extracting views
                
                // MARK: - Border & blur effect
                
                VStack(alignment: .leading) {
                    
                    Text("Border & blur effect")
                        .fontWeight(.heavy)
                        .font(.title)
                    Image(systemName: "hands.and.sparkles.fill")
                        .resizable()
                        .scaledToFill()
                    // border effect
                        .border(Color.pink, width: 10)
                        .frame(width: 200, height: 200)
                }
                // blur effect
                .blur(radius: 1.0)
                // end of group
                
                // MARK: - Clip Shape & color inverted effect
                
                VStack(alignment: .leading) {
                    
                    Text("Clip Shape & color inverted effect")
                        .fontWeight(.heavy)
                        .font(.title)
                    Image(systemName: "hands.and.sparkles.fill")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 300, height: 300)
                        .clipShape(Circle())
                    
                    
                }
                .colorInvert()
                // end of group
                
                // MARK: - Brigthness effect
                
                VStack(alignment: .leading) {
                    Text("Brigthness effect")
                        .fontWeight(.heavy)
                        .font(.title)
                    
                    Image(systemName: "hands.and.sparkles.fill")
                        .resizable()
                        .scaledToFill()
                        .brightness(0.3)
                }
                // end of group
                
                // MARK: - Color multiply & Contrast effect
                
                VStack(alignment: .leading) {
                    Text("Color multiply & Contrast effect")
                        .fontWeight(.heavy)
                        .font(.title)
                    
                    Image(systemName: "hands.and.sparkles.fill")
                        .resizable()
                        .scaledToFill()
                    
                }
                // color effect
                .colorMultiply(.blue)
                // Defines the content shape for hit testing.
                .contentShape(Circle())
                .contrast(3.0)
                // end of group
                
                // MARK: - Blend mode effect
                
                VStack(alignment: .leading) {
                    Text("Blend mode effect")
                        .fontWeight(.heavy)
                        .font(.title)
                    
                    HStack {
                        BlendExamplesView()
                    }
                }
                
            }
            .listStyle(PlainListStyle())
            // accent color effect
            .accentColor(.green)
        }
        .padding(.horizontal)
    }
    
    private var grayScale: some View {
        VStack(alignment: .leading) {
            Text("Gray scale")
                .fontWeight(.heavy)
                .font(.title)
            
            Image(systemName: "hands.and.sparkles.fill")
                .resizable()
                .scaledToFill()
                .grayscale(0.30)
                .hoverEffect(.highlight)
        }
        
    }
    
    private var rotation: some View {
        VStack(alignment: .leading) {
            Text("Rotation with shadow")
                .fontWeight(.heavy)
                .font(.title)
            
                .padding(.bottom, 60)
            Image(systemName: "hands.and.sparkles.fill")
                .resizable()
                .scaledToFill()
                .clipped()
                .shadow(radius: 10)
                .rotationEffect(Angle(degrees: 30))
                .padding(.bottom, 70)
                .padding(.horizontal, 30)
        }
    }
    
    private var masking: some View {
        VStack(alignment: .leading) {
            Text("Masking")
                .fontWeight(.heavy)
                .font(.title)
            
            Image(systemName: "hands.and.sparkles.fill")
                .resizable()
                .scaledToFill()
                .mask(Text("An example to show how to mask an image with a text on top")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .font(.title)
                      
                    .multilineTextAlignment(.center)
                    .frame(width:320, height: 220))
            
        }
        
    }
}

#Preview {
    
        EffectsModifiersView()
}

struct BlendExamplesView: View {
    var body: some View {
        VStack {
            Color("Medium", bundle: .module).frame(width: 50, height: 50, alignment: .center)
            Color.red.frame(width: 50, height: 50, alignment: .center)
                .rotationEffect(.degrees(45))
                .padding(-20)
            // blend mode
                .blendMode(.colorBurn)
        }
        .padding(20)
        VStack {
            Color("Medium", bundle: .module).frame(width: 50, height: 50, alignment: .center)
            Color.red.frame(width: 50, height: 50, alignment: .center)
                .rotationEffect(.degrees(45))
                .padding(-20)
            // blend mode
                .blendMode(.luminosity)
        }
        .padding(20)
        VStack {
            Color("Medium", bundle: .module).frame(width: 50, height: 50, alignment: .center)
            Color.red.frame(width: 50, height: 50, alignment: .center)
                .rotationEffect(.degrees(45))
                .padding(-20)
            // blend mode
                .blendMode(.lighten)
        }
        .padding(20)
        
        VStack {
            Color("Medium", bundle: .module).frame(width: 50, height: 50, alignment: .center)
            Color.red.frame(width: 50, height: 50, alignment: .center)
                .rotationEffect(.degrees(45))
                .padding(-20)
            // blend mode
                .blendMode(.exclusion)
        }
        .padding(20)
        
    }
}

// MARK: - HASHABLE

extension EffectsModifiersView {
    
    static func == (lhs: EffectsModifiersView, rhs: EffectsModifiersView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


