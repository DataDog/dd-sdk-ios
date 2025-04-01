//
//  TogglesView.swift
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

import SwiftUI

///
/// Examples on how to use TOGGLES in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/toggle
///
struct TogglesView: View, Comparable {
    
    let id: String = "TogglesView"
    
    @State var isBasicToggleOn: Bool = true
    @State var isSwitchToggleOn: Bool = true
    @State var isCustomToggleOn: Bool = true
    @State var isButtonToggleOn: Bool = true
    
    var body: some View {
        PageContainer(
            content:
                Group {
                    VStack(alignment: .leading) {
                        DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/toggle", name: "TOGGLES")
                        
                        GroupBox {
                            Text("Toggles")
                                .fontWeight(.heavy)
                                .font(.title)
                            Text("You create a toggle by providing an isOn binding and a label. Bind isOn to a Boolean property that determines whether the toggle is on or off")
                                .fontWeight(.light)
                                .font(.title2)
                            defaultToggle
                                .modifier(Divided())
                            switchToggle
                                .modifier(Divided())
                            customToggle
                                .modifier(Divided())
                            toggleWithStyle
                        }
                        
                        Spacer()
                        
                        ContributedByView(name: "Freddy Hernandez Jr",
                                          link: "https://github.com/freddy1h")
                        .padding(.top, 80)
                    }
                }
        )
    }
    
    private var defaultToggle: some View {
        Group {
            Text("The default toggle style is 'switch', which draws a rounded rectangle with a tint color, usually green, that can be changed.")
                .fontWeight(.light)
                .font(.title2)
            Toggle(
                isOn: $isBasicToggleOn,
                label: {
                    Text("Default Toggle Style")
                }
            )
            .padding(.trailing, 8)
            .toggleStyle(.automatic)
        }
    }
    
    private var switchToggle: some View {
        Toggle(
            isOn: $isSwitchToggleOn,
            label: {
                Text("Switch Toggle Style")
            }
        )
        .padding(.trailing, 8)
        .tint(Color.purple)
        .toggleStyle(.switch)
    }
    
    private var customToggle: some View {
        Group {
            Text("In this custom toggle, the background color has changed and there is a narrower indicator when the toggle is switched.")
                .fontWeight(.light)
                .font(.title2)
            Toggle(
                isOn: $isCustomToggleOn,
                label: {
                    Text("Custom Toggle Style")
                }
            )
            .padding(.trailing, 8)
            .toggleStyle(.custom)
            .frame(maxWidth: .infinity)
        }
    }
    
    private var toggleWithStyle: some View {
        Group {
            Text("In this toggle we have assigned a custom BUTTON style, therefore the behaviour of the component keeps working as a toggle but it looks like a button, switching on and off the associated value.")
                .fontWeight(.light)
                .font(.title2)
            Toggle(
                isOn: $isButtonToggleOn,
                label: {
                    Text("Button Toggle Style")
                        .frame(maxWidth: .infinity)
                }
            )
            .toggleStyle(.button)
            .tint(Color.purple)
        }
    }
}

struct CustomToggleStyle: ToggleStyle {
    func makeBody(configuration: ToggleStyle.Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button(
                action: {
                    configuration.isOn = !configuration.isOn
                },
                label: {
                    Rectangle()
                        .fill(configuration.isOn ? Color.purple : .blue.opacity(0.5))
                        .frame(
                            width: 50,
                            height: 30
                        )
                        .overlay(
                            Ellipse()
                                .frame(
                                    width: 20,
                                    height: configuration.isOn ? 20 : 5
                                )
                                .foregroundColor(.white)
                                .offset(
                                    x: configuration.isOn ? 11 : -11,
                                    y: 0
                                )
                                .animation(.easeInOut, value: configuration.isOn)
                        )
                        .cornerRadius(20)
                }
            )
            .buttonStyle(.plain)
        }
    }
}

extension ToggleStyle where Self == CustomToggleStyle {
    static var custom: CustomToggleStyle { CustomToggleStyle() }
}

#Preview {
    
        TogglesView()
    
}

// MARK: - HASHABLE

extension TogglesView {
    static func == (lhs: TogglesView, rhs: TogglesView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
