//
//  ButtonsComponentsView.swift
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
/// A view showing different usages
/// of the SwiftUI BUTTON control
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/button
///
struct ButtonsComponentsView: View, Comparable {
    
    // MARK: - Properties
    
    let id: String = "ButtonsComponentsView"
    
    @State private var fruits = [ "Apple", "Banana", "Papaya", "Mango"]
    
    @State private var pastedText: String = ""
    
    /// configuration of the first button: background color
    @State private var color: Color = Color.clear
    /// configuration of the first button: border color
    @State private var colorBorder: Color = Color.accentColor
    /// configuration of the first button: border width
    @State private var borderWidth: Double = 1
    /// configuration of the first button: custom font
    @State private var font: UIFont = UIFont.preferredFont(forTextStyle: .body)
    
    // MARK: - Interactive button configuration
    /// radius configuration
    @State private var radius2: CGFloat = 10.0
    /// frame width
    @State private var buttonWidth: CGFloat = 100
    /// frame height
    @State private var buttonHeight: CGFloat = 44
    /// configuration of the : background color
    @State private var color2: Color = Color.clear
    /// configuration of the first button: border color
    @State private var colorBorder2: Color = Color.accentColor
    /// configuration of the first button: border width
    @State private var borderWidth2: Double = 1
    /// the style for the button's title
    @State private var textStyle2: UIFont.TextStyle = .body
    
    
    // MARK: - Body
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView {
            
            VStack(alignment: .leading) {
                
                DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/button", name: nil)
                
                Text("Given an action and a label you can create a button. When a user clicks or taps the button, an action—a method or closure property—is triggered. The label is a view that can display text, an icon, or both to describe the operation of the button. Any type of view, such as a Text view for text-only labels, can be the label of a button.")
                    .fontWeight(.light)
                    .font(.title2)
                    .padding(.bottom)
                // MARK: - basics of buttons
                Group {
                    customizableButton
                        .modifier(Divided())
                    roundedButtons
                        .modifier(Divided())
                    customShapeButtons
                        .modifier(Divided())
                    labelStyledButton
                        .modifier(Divided())
                    strokedBorderButtons
                        .modifier(Divided())
                    plainBackgroundButtons
                        .modifier(Divided())
                    imagesInButtons
                        .modifier(Divided())
                    buttonsWithIcons
                        .modifier(Divided())
                    buttonWithLabels
                        .modifier(Divided())
                    styledButtons
                        .modifier(Divided())
                }
                
                ContributedByView(name: "Barbara Martina",
                                  link: "https://github.com/barbaramartina")
                .padding(.top, 80)
            }
        })
        
    }
    
    
    private var imagesInButtons: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Button with image")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("An Image view can be used instead of the usual title, the image just needs to be set as the label of the button.")
                    .fontWeight(.light)
                    .font(.title2)
                Button(action: {}, label: {
                    Image(systemName: "person")
                        .padding()
                })
                .border(Color.accentColor, width: 5)
                .padding(.leading, Style.HorizontalPadding.small.rawValue)
            }
        }
    }
    
    private var buttonsWithIcons: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Button with icon & label")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("Any other combination of views can be used as the 'label' of the button, this allows for a lot of flexibility when it comes to have clicks areas which are bigger, while conserving the highlighting state of the button component.")
                Button(action: {}, label: {
                    Label {
                        Text("Add person")
                            .modifier(ButtonFontModifier())
                    } icon: {
                        Image(systemName: "person")
                            .padding()
                    }
                })
                .modifier(ButtonBorderModifier())
                .padding(.leading, Style.HorizontalPadding.small.rawValue)
            }
        }
    }
    
    private var buttonWithLabels: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Button with label")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("In the simplest of the forms, a button can be just connected to a text.")
                    .fontWeight(.light)
                    .font(.title2)
                Button(action: {}, label: {
                    Text("Add ")
                        .modifier(ButtonFontModifier())
                })
                .modifier(ButtonBorderModifier())
                .padding(.leading, Style.HorizontalPadding.small.rawValue)
            }
        }
    }
    
    private var styledButtons: some View {
        Group {
            GroupBox {
                VStack(alignment: .leading) {
                    Text("BorderlessButtonStyle")
                        .fontWeight(.heavy)
                        .font(.title)
                    Text("There is an specific button style called BorderlessButtonStyle which can be used to create simple buttons.")
                        .fontWeight(.light)
                        .font(.title2)
                    Button("Style me: borderless", action: {})
                        .buttonStyle(BorderlessButtonStyle())
                        .padding()
                }
            }
            .modifier(Divided())
            GroupBox {
                VStack(alignment: .leading) {
                    Text("PlainButtonStyle")
                        .fontWeight(.heavy)
                        .font(.title)
                    Text("A button style that, when in an idle state, does not style or decorate its content; instead, it may apply a visual effect to show if the button is pressed, focused, or enabled.")
                        .fontWeight(.light)
                        .font(.title2)
                    Button("Style me: plain", action: {})
                        .buttonStyle(PlainButtonStyle())
                        .padding()
                }
            }
        }
    }
    
    private var labelStyledButton: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("A button label can have different styles")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("A modifier can be used to set a specific style for all labels within a view, to show only an icon, or only the title or both.")
                    .fontWeight(.light)
                    .font(.title2)
                Button("Label Syle Icon Only", systemImage: "message.badge",  action: {})
                    .modifier(ButtonFontModifier(font: Font(UIFont.preferredFont(forTextStyle: textStyle2))))
                    .background(color2)
                    .labelStyle(.iconOnly)
                    .modifier(RoundedBordersModifier(radius: 10,
                                                     lineWidth: CGFloat(borderWidth),
                                                     color: colorBorder))
                    .padding(.leading, Style.HorizontalPadding.small.rawValue)
                Button("Label Syle Title Only", systemImage: "message.badge",  action: {})
                    .modifier(ButtonFontModifier(font: Font(UIFont.preferredFont(forTextStyle: textStyle2))))
                    .background(color2)
                    .labelStyle(.titleOnly)
                    .modifier(RoundedBordersModifier(radius: 10,
                                                     lineWidth: CGFloat(borderWidth),
                                                     color: colorBorder))
                    .padding(.leading, Style.HorizontalPadding.small.rawValue)
                Button("Label Syle Icon and Title", systemImage: "message.badge",  action: {})
                    .modifier(ButtonFontModifier(font: Font(UIFont.preferredFont(forTextStyle: textStyle2))))
                    .background(color2)
                    .labelStyle(.titleAndIcon)
                    .modifier(RoundedBordersModifier(radius: 10,
                                                     lineWidth: CGFloat(borderWidth),
                                                     color: colorBorder))
                    .padding(.leading, Style.HorizontalPadding.small.rawValue)
            }
        }
    }
    
    private var customizableButton: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Customizable button")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("At continuation, we show a button and some properties, so that you can adjust them interactively and see how the button changes. If you change the font style to extraLargeTitle, you will need to increase the width of the button to make the size fit. Since we're showcasing how a fixed size affects the content of a button in this case, we choose to fix a width. But you can easily give your buttons a min and max width values to make them react to different font styles.")
                    .fontWeight(.light)
                    .font(.title2)
                Button("change me", systemImage: "message.badge",  action: {})
                    .frame(width: buttonWidth, height: buttonHeight)
                    .modifier(ButtonFontModifier(font: Font(UIFont.preferredFont(forTextStyle: textStyle2))))
                    .background(color2)
                    .modifier(RoundedBordersModifier(radius: radius2,
                                                     lineWidth: CGFloat(borderWidth2),
                                                     color: colorBorder2))
                    .padding(.leading, Style.HorizontalPadding.small.rawValue)
                
                ColorPicker("Background color:",
                            selection: $color2,
                            supportsOpacity: false)
                
                ColorPicker("Border color:",
                            selection: $colorBorder2,
                            supportsOpacity: false)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Border width:")
                        Slider(value: $borderWidth2, in: 0...10, step: 1, label: {
                            Text("\(borderWidth2)")
                        }, minimumValueLabel: {
                            Text("0")
                        }, maximumValueLabel: {
                            Text("10")
                        }, onEditingChanged:{_ in } )
                    }
                    Text("current value: \(Int(borderWidth2))")
                        .font(.footnote)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Frame width:")
                        Slider(value: $buttonWidth, in: 50...300, step: 1, label: {
                            Text("\(Int(buttonWidth))")
                        }, minimumValueLabel: {
                            Text("50")
                        }, maximumValueLabel: {
                            Text("300")
                        }, onEditingChanged:{_ in } )
                    }
                    Text("current value: \(Int(buttonWidth))")
                        .font(.footnote)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Frame height:")
                        Slider(value: $buttonHeight, in: 35...100, step: 1, label: {
                            Text("\(Int(buttonHeight))")
                        }, minimumValueLabel: {
                            Text("35")
                        }, maximumValueLabel: {
                            Text("100")
                        }, onEditingChanged:{_ in } )
                    }
                    Text("current value: \(Int(buttonHeight))")
                        .font(.footnote)
                }
                HStack {
                    Text("Font Style:")
                    UIFontTextStylePicker(selection: $textStyle2)
                }
            }
        }
    }
    
    
    // MARK: - views
    
    private var roundedButtons: some View {
        // Contextual information: a short intro to the elements we are showcasing
        GroupBox {
            VStack(alignment: .leading) {
                Text("Rounded Button")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("One of the most usual designs for buttons is to include rounded corners. You can see how to achieve that here, using a custon view modifier.")
                    .fontWeight(.light)
                    .font(.title2)
                
                Button(action: {},
                       label: {
                    Text("Click")
                        .modifier(ButtonFontModifier(font: Font(font)))
                        .modifier(RoundedBordersModifier(radius: 10,
                                                         lineWidth: CGFloat(borderWidth),
                                                         color: colorBorder))
                })
                .background(color)
                .padding(.leading, Style.HorizontalPadding.small.rawValue)
                
                ColorPicker("Background color:",
                            selection: $color,
                            supportsOpacity: false)
                
                ColorPicker("Border color:",
                            selection: $colorBorder,
                            supportsOpacity: false)
                
                HStack {
                    Text("Border width:")
                        .fontWeight(.light)
                        .font(.title2)
                    Slider(
                        value: $borderWidth,
                        in: 0...10,
                        step: 1,
                        onEditingChanged: {_ in }
                    )
                    
                }
            }
        }
        
    }
    
    private var customShapeButtons: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Specific Rounded borders with custom shape")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("Sometimes we want to give the borders of a button a rounded style, but not to all of them. This can be achieved with a custom shape as an overlay for the standard Button View. This can also be achieved by using an UnevenRectangle as a clip shape and giving each corner a different radius.")
                    .fontWeight(.light)
                    .font(.title2)
                
                HStack {
                    Button(action: {},
                           label: {
                        Text("Click")
                            .modifier(ButtonFontModifier())
                            .overlay(
                                RoundedCorners(tl: 10,
                                               tr: 0,
                                               bl: 0,
                                               br: 10)
                                .stroke(Color.accentColor, lineWidth: 5)
                            )
                    })
                    Button(action: {},
                           label: {
                        Text("Click")
                            .modifier(ButtonFontModifier())
                            .border(.black, width: 3)
                            .clipShape(
                                UnevenRoundedRectangle(topLeadingRadius: 3,
                                                       bottomLeadingRadius: 18,
                                                       bottomTrailingRadius: 0,
                                                       topTrailingRadius: 10)
                            )
                            .overlay(
                                UnevenRoundedRectangle(topLeadingRadius: 3,
                                                       bottomLeadingRadius: 18,
                                                       bottomTrailingRadius: 0,
                                                       topTrailingRadius: 10)
                                .stroke(Color.accentColor, lineWidth: 5)
                            )
                    })
                }
                .padding(.leading, Style.HorizontalPadding.small.rawValue)
            }
        }
    }
    
    private var strokedBorderButtons: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Stroked borders")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("Borders can also be drawn with a certain stroke pattern by using an overlay and a specific StrokeStyle.")
                    .fontWeight(.light)
                    .font(.title2)
                Button(action: {}) {
                    Text("Click")
                        .modifier(ButtonFontModifier())
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.accentColor,
                                        style: StrokeStyle(lineWidth: 5, dash: [10]))
                        )
                }
                .padding(.leading, Style.HorizontalPadding.small.rawValue)
            }
        }
        
    }
    
    private var plainBackgroundButtons: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Button with plain background")
                    .fontWeight(.heavy)
                    .font(.title)
                Text("Using the background modifier an color can be added as the background of the button.")
                    .fontWeight(.light)
                    .font(.title2)
                Button(action: {}, label: {
                    Text("Click")
                        .padding()
                        .modifier(ButtonFontModifier())
                })
                .background(Color("Medium", bundle: .module))
                .padding(.leading, Style.HorizontalPadding.small.rawValue)
            }
        }
        
    }
}

// MARK: - previews

#Preview {
    
        ButtonsComponentsView()
            
}

// MARK: - custom borders shape
//. thanks to https://stackoverflow.com/questions/56760335/round-specific-corners-swiftui

struct RoundedCorners: Shape {
    var tl: CGFloat = 0.0
    var tr: CGFloat = 0.0
    var bl: CGFloat = 0.0
    var br: CGFloat = 0.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.size.width
        let h = rect.size.height
        
        // Make sure we do not exceed the size of the rectangle
        let tr = min(min(self.tr, h/2), w/2)
        let tl = min(min(self.tl, h/2), w/2)
        let bl = min(min(self.bl, h/2), w/2)
        let br = min(min(self.br, h/2), w/2)
        
        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr,
                    startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                    startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl,
                    startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl,
                    startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        return path
    }
    
    
}

// MARK: - HASHABLE

extension ButtonsComponentsView {
    
    static func == (lhs: ButtonsComponentsView, rhs: ButtonsComponentsView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



