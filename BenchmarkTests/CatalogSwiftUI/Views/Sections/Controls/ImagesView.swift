//
//  ImagesComponentView.swift
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

//

import SwiftUI

///
/// A view showing different usages
/// of the SwiftUI IMAGE control
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/image
///
struct ImagesComponentView: View, Comparable {
    
    let id: String = "ImagesComponentView"
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/image", name: "IMAGE VIEW")
            
            sfSymbols
                .modifier(Divided())
            imagesFromBundle
                .modifier(Divided())
            fixedFrameImages
                .modifier(Divided())
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            Spacer()
            
        })
        // end of page container
        
    }
    
    // Contextual information: a short intro to the elements we are showcasing
    private var sfSymbols: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Images with SF Symbols")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("SF Symbols is a collection of iconography that has over 5,000 symbols and is made to work perfectly with San Francisco, the system font used by Apple platforms. Symbols automatically align with text and are available in three scales and nine weights. Using vector graphics editing software, they can be altered and exported to produce unique symbols with shared accessibility features and design elements. With SF Symbols 5, you can now create bespoke symbols with improved tools, over 700 new symbols, and a variety of expressive animations. You can find more about SF Symbols in [the SF Official page](https://developer.apple.com/design/resources/#sf-symbols)")
                    .fontWeight(.light)
                    .font(.title2)
                ScrollView(.horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        Image(systemName: "house.circle")
                        Image(systemName: "square.circle")
                        Image(systemName: "dpad")
                        Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                        Image(systemName: "eraser")
                        Image(systemName: "paperplane.circle")
                        Image(systemName: "externaldrive.connected.to.line.below")
                        Image(systemName: "keyboard.badge.eye")
                        Image(systemName: "printer.dotmatrix.fill")
                        Image(systemName: "figure.2")
                        Image(systemName: "figure.2.circle")
                        Image(systemName: "eye")
                        Image(systemName: "eye.fill")
                        Image(systemName: "textformat.size")
                        Image(systemName: "checkmark.seal.fill")
                        Image(systemName: "exclamationmark.bubble.circle")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
            }
        }
    }
    
    private var imagesFromBundle: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Images from Bundle")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("Images can be uploaded from the app bundle, just the same as with UIKit, images can be scaled, resized, tiled, framed and also you can overlays on top of images to mask them to different shapes.")
                    .fontWeight(.light)
                    .font(.title2)
                // Credits: https://pixabay.com/photos/dog-pet-corgi-animal-canine-6394502/
                Text("Image scaled to fit")
                    .fontWeight(.semibold)
                    .padding(.top)
                Image(systemName: "hands.and.sparkles.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .modifier(Divided())
                Text("Image scaled to fill")
                    .fontWeight(.semibold)
                Image(systemName: "hands.and.sparkles.fill")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .modifier(Divided())
                Text("Aspect ratio")
                    .fontWeight(.semibold)
                Image(systemName: "hands.and.sparkles.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .modifier(Divided())
                Text("Circled overlay")
                    .fontWeight(.semibold)
                Image(systemName: "hands.and.sparkles.fill")
                    .resizable()
                    .scaledToFit()
                    .overlay(
                        Color.gray
                            .opacity(0.5)
                    )
                    .clipShape(Circle())
                    .frame(width: 200, height: 200)
                
            }
        }
    }
    
    private var fixedFrameImages: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Image fitting in a fixed frame")
                    .fontWeight(.semibold)
                Image(systemName: "hands.and.sparkles.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250, alignment: .topLeading)
                    .border(Color.blue)
                    .clipped()
                
                Text("Tiled Image: A mode to repeat the image at its original size, as many times as necessary to fill the available space.")
                    .fontWeight(.semibold)
                Image("github", bundle: .module)
                    .resizable(resizingMode: .tile)
                    .frame(width: 300, height: 900, alignment: .topLeading)
                    .border(Color.blue)
            }
        }
    }
    
}

#Preview {
    
        ImagesComponentView()
            
    
}

// MARK: - HASHABLE

extension ImagesComponentView {
    
    static func == (lhs: ImagesComponentView, rhs: ImagesComponentView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


