//
//  TextModifiersView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2022 Barbara Martina
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
/// Examples on how to use  TEXT MODIFIERS  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/text
///

struct TextModifiersView: View, Comparable {
    
    let id: String = "TextModifiersView"
    
    @State private var text1: String = ""
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView {
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/text", name: "TEXT MODIFIERS")
            
            Group {
                GroupBox {
                    VStack(alignment: .leading) {
                        Text("Text view modifiers")
                            .fontWeight(.heavy)
                            .font(.title)
                        
                        Text("Examples of modifiers that can be applied to Text Views")
                            .fontWeight(.light)
                            .font(.title2)
                        // Font weights
                        Group {
                            Text("Font Weight Light")
                                .fontWeight(.light)
                                .font(.title2)
                            Text("Font Weight Medium")
                                .fontWeight(.medium)
                            Text("Font Weight Bold")
                                .fontWeight(.bold)
                            Text("Font Weight regular")
                                .fontWeight(.regular)
                            Text("Font Weight Semibold")
                                .fontWeight(.semibold)
                            Text("Font Weight thin")
                                .fontWeight(.thin)
                            Text("Font Weight Ultralight")
                                .fontWeight(.ultraLight)
                                .font(.title3)
                            Text("Font Weight Black")
                                .fontWeight(.heavy)
                        }
                    }
                }
                // end of Font weights
                .modifier(Divided())
                
                GroupBox {
                    VStack(alignment: .leading) {
                        Text("Font type Headline")
                            .font(.headline)
                        Text("Font type Subheadline")
                            .font(.subheadline)
                        Text("Font type Large title")
                            .font(.largeTitle)
                        Text("Font type Title")
                            .font(.title)
                        Text("Font type title 2")
                            .font(.title2)
                        Text("Font type title 3")
                            .font(.title3)
                        Text("Font type Body")
                            .font(.body)
                        Text("Font type Callout")
                            .font(.callout)
                        Text("Font type Caption")
                            .font(.caption)
                        Text("Font type Caption 2")
                            .font(.caption2)
                        Text("Font type Footnote")
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                }
                .modifier(Divided())
                // end of font types
                
                // Foreground colors
                GroupBox {
                    Text("Foregroung color: A pink text")
                        .foregroundColor(.pink)
                        .frame(maxWidth: .infinity)
                    
                }
                .modifier(Divided())
                // end of foreground colors
                
                // Line limit
                GroupBox {
                    
                    Text("Line limit: A very long text that can only occupy 2 lines. A very long text that can only occupy 2 lines.A very long text that can only occupy 2 lines.A very long text that can only occupy 2 lines. ")
                        .lineLimit(2)
                        .padding()
                }
                .modifier(Divided())
                // end of line limit
                
                // Backgrounds
                GroupBox {
                    
                    Text("Backgrounds: a text with a text background")
                        .font(.title)
                        .background(Text("AAAAAAAAAA")
                            .fontWeight(.ultraLight)
                            .font(.title3))
                        .padding()
                    
                    Text("Backgrounds: a text with a color as background")
                        .font(.title)
                        .background(.blue)
                        .padding()
                    
                    Text("Backgrounds: a text with an image background")
                        .font(.title)
                        .background(Image(systemName: "person")
                            .resizable()
                            .foregroundColor(Color("Medium", bundle: .module))
                            .frame(width: 100,
                                   height: 100,
                                   alignment: .center))
                        .padding()
                }
                .modifier(Divided())
                
                // Opacity
                GroupBox {
                    
                    VStack(alignment: .leading) {
                        Text("A text with opacity 0.3")
                            .opacity(0.3)
                        Text("A text with opacity 0.6")
                            .opacity(0.6)
                        Text("A text with opacity 0.9")
                            .opacity(0.9)
                    }
                    .frame(maxWidth: .infinity)
                }
                .modifier(Divided())
                // end of opacity
                
                // Bold , underlined..
                GroupBox {
                    
                    VStack(alignment: .leading) {
                        Text("Bold text")
                            .bold()
                        Text("Underlined text")
                            .underline()
                        Text("Italic text")
                            .italic()
                    }
                    .frame(maxWidth: .infinity)
                    
                }
                .modifier(Divided())
                // end of bold and underlined
                
            }
            
            Group {
                
                // tightening
                GroupBox {
                    
                    Text("Example of a text which is slightly long for a line and we set a modifier to allow the characters to tighten")
                        .lineLimit(1)
                        .allowsTightening(false)
                        .padding()
                    
                    Text("Example of a text which is slightly long for a line and we set a modifier to allow the characters to tighten")
                        .lineLimit(1)
                        .allowsTightening(true)
                        .padding()
                }
                .modifier(Divided())
                // end of tightening
                
                // Layout direction
                GroupBox {
                    
                    VStack(alignment: .leading) {
                        Link(destination: Text("https://developer.apple.com/documentation/swiftui/environmentvalues/layoutdirection"),
                             label: "Layout Direction")
                        Text("Preparing a text to adjust to the layout direction change")
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .modifier(Divided())
                // end of layout direction
                
                // text selection
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("textSelection():")
                            .padding(.top, 3)
                            .textSelection(.enabled)
                        
                        Text("Controls whether people can select text within this view. Sometimes we need to copy useful information from Text views, we can apply this to individual or container to make each text selectable.")
                        
                        Text("Long press to copy")
                        
                        Text("iOS 15+")
                            .fontWeight(.light)
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .modifier(Divided())
                // end of text selection
                
                // text rotation
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text Rotation Effect")
                        
                        Text("This text is rotated")
                            .rotation3DEffect(Angle(degrees: 180), axis: (x: 1, y: 0, z: 0))
                        
                        Text("iOS 13+")
                            .fontWeight(.light)
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(Divided())
                // end of text rotation
                
                // text Shadow
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text Shadow")
                            .shadow(color: .green, radius: 2, x: 2, y: 2)
                        
                        Text("iOS 13+")
                            .fontWeight(.light)
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(Divided())
                // end of text Shadow
                
                // text tracking
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Space between characters")
                            .tracking(2.5)
                        
                        Text("iOS 13+")
                            .fontWeight(.light)
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(Divided())
                // end of text tracking
                
                // Keyboard types
                GroupBox {
                    
                    Group {
                        TextField("Text field with alphabet keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.alphabet)
                            .padding()
                        
                        TextField("Text field with ascii keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.asciiCapable)
                            .padding()
                        
                        TextField("Text field with ascii number pad keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.asciiCapableNumberPad)
                            .padding()
                        
                        TextField("Text field with decimal pad keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.decimalPad)
                            .padding()
                        
                        TextField("Text field with email address keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.emailAddress)
                            .padding()
                        
                        TextField("Text field with name phone pad keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.namePhonePad)
                            .padding()
                        
                        TextField("Text field with number pad keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.numberPad)
                            .padding()
                        
                        TextField("Text field with numbers and punctuation keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.numbersAndPunctuation)
                            .padding()
                        
                        TextField("Text field with twitter keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.twitter)
                            .padding()
                        
                        TextField("Text field with web search keyboard", text: $text1)
                            .keyboardType(UIKeyboardType.webSearch)
                            .padding()
                    }
                    
                }
                .modifier(Divided())
                // end of keyboard examples
                
            }
            
            
        })
        // end of page container
    }
}

#Preview {
    
        TextModifiersView()
    
}

// MARK: - HASHABLE

extension TextModifiersView {
    
    static func == (lhs: TextModifiersView, rhs: TextModifiersView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}
