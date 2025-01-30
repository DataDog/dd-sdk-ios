//
//  StylesView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Barbara Martina
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
/// Multiple examples on how to apply styles to different SwiftUI
/// components
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/view-styles
///
struct StylesView: View, Comparable {
    
    let id: String = "StylesView"
    
    @State private var selectedPickerString: String = ""
    @State private var toggleValue: Bool = false
    
    var body: some View {
        
        PageContainer(content:
                        VStack(alignment: .leading) {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/view-styles", name: "STYLE VIEW")
            
            // contextual information
            Text("Styling views is giving the views a certain appereance. Swift provides styles depending on the type of view, and it also allows you to define your custom style for a particular type of view.")
                .fontWeight(.light)
                .font(.title2)
                .modifier(Divided())
            gauges
                .modifier(Divided())
            progress
                .modifier(Divided())
            pickers
                .modifier(Divided())
            toggles
                .modifier(Divided())
            buttons
                .modifier(Divided())
            menues
            
        }
        )
    }
    
    private var pickers: some View {
        // styling Pickers
        // https://developer.apple.com/documentation/swiftui/pickerstyle
        GroupBox {
            Text("Styling Pickers")
                .fontWeight(.heavy)
                .font(.title)
            HStack {
                Text("Automatic style:")
                Spacer()
                Picker("Option", selection: $selectedPickerString) {
                    Text("Option 1")
                    Text("Option 2")
                    Text("Option 3")
                }
                .pickerStyle(.automatic)
            }
            HStack {
                Text("Inline style:")
                Spacer()
                Picker("Option", selection: $selectedPickerString) {
                    Text("Option 1")
                    Text("Option 2")
                    Text("Option 3")
                }
                .pickerStyle(.inline)
            }
            HStack {
                Text("Menu style:")
                Spacer()
                Picker("Option", selection: $selectedPickerString) {
                    Text("Option 1")
                    Text("Option 2")
                    Text("Option 3")
                }
                .pickerStyle(.menu)
            }
            HStack {
                Text("Segmented style:")
                Spacer()
                Picker("Option", selection: $selectedPickerString) {
                    Text("Option 1")
                    Text("Option 2")
                    Text("Option 3")
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text("Menu style:")
                Spacer()
                Picker("Option", selection: $selectedPickerString) {
                    Text("Option 1")
                    Text("Option 2")
                    Text("Option 3")
                }
                .pickerStyle(.wheel)
            }
            
            HStack {
                Text("Navigation Link style:")
                Spacer()
                Picker("Option", selection: $selectedPickerString) {
                    Text("Option 1")
                    Text("Option 2")
                    Text("Option 3")
                }
                .pickerStyle(.navigationLink)
            }
        }
        // end of styling pickers
        
    }
    
    private var buttons: some View {
        // Styling buttons with all the possible already implemented styles in Swift + 1 custom style
        GroupBox {
            Text("Styling buttons")
                .fontWeight(.heavy)
                .font(.title)
            HStack {
                Text("Automatic button style: ")
                    .fontWeight(.light)
                    .font(.title2)
                Spacer()
                Button("Example action") { }
                    .buttonStyle(.automatic)
            }
            HStack {
                Text("Bordered button style: ")
                    .fontWeight(.light)
                    .font(.title2)
                Spacer()
                Button("Example action") { }
                    .buttonStyle(.bordered)
            }
            HStack {
                Text("Border less button style: ")
                    .fontWeight(.light)
                    .font(.title2)
                Spacer()
                Button("Example action") { }
                    .buttonStyle(.borderless)
            }
            HStack {
                Text("Border prominent less button style: ")
                    .fontWeight(.light)
                    .font(.title2)
                Spacer()
                Button("Example action") { }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Text("Plain button style: ")
                    .fontWeight(.light)
                    .font(.title2)
                Spacer()
                Button("Example action") { }
                    .buttonStyle(.plain)
            }
            HStack {
                Text("My own button style: ")
                    .fontWeight(.light)
                    .font(.title2)
                Spacer()
                Button("Example action") { }
                    .buttonStyle(MyOwnButtonStyle())
            }
            
        }
        // end buttons styles
    }
    
    private var toggles: some View {
        // styling Toggles
        // https://developer.apple.com/documentation/swiftui/togglestyle
        GroupBox {
            Text("Styling Toggles")
                .fontWeight(.heavy)
                .font(.title)
            HStack {
                Text("Automatic style:")
                Spacer()
                Toggle(isOn: $toggleValue) {
                    Text("Toggle")
                }
                .toggleStyle(.automatic)
            }
            HStack {
                Text("Button style:")
                Spacer()
                Toggle(isOn: $toggleValue) {
                    Text("Toggle")
                }
                .toggleStyle(.button)
            }
            HStack {
                Text("Switch style:")
                Spacer()
                Toggle(isOn: $toggleValue) {
                    Text("Toggle")
                }
                .toggleStyle(.switch)
            }
            
        }
        // end styling toggles
    }
    
    private var menues: some View {
        // styling menues
        GroupBox {
            Text("Styling Menues")
                .fontWeight(.heavy)
                .font(.title)
            HStack {
                Text("Button style:")
                Spacer()
                Menu("Open Menu") {
                    Button("Menu option 1", action: {})
                    Button("Menu option 2",
                           action: {})
                }
                .menuStyle(ButtonMenuStyle())
            }
            HStack {
                Text("Automatic style:")
                Spacer()
                Menu("Open Menu") {
                    Button("Menu option 1", action: {})
                    Button("Menu option 2",
                           action: {})
                }
                .menuStyle(.automatic)
            }
            HStack {
                Text("My own style:")
                Spacer()
                Menu("Open Menu") {
                    Button("Menu option 1",
                           action: {})
                    Button("Menu option 2",
                           action: {})
                }
                .menuStyle(MyOwnMenuStyle())
            }
        }
        // end of styling menues
    }
    
    private var progress: some View {
        GroupBox {
            Group {
                // https://developer.apple.com/documentation/swiftui/progressviewstyle
                Text("Styling progress indicator")
                    .fontWeight(.heavy)
                    .font(.title)
                VStack {
                    Text("Automatic style:")
                    Spacer()
                    ProgressView("Downloading…",
                                 value: 76,
                                 total: 100)
                    .progressViewStyle(.automatic)
                }
                VStack {
                    Text("Linear style:")
                    Spacer()
                    ProgressView("Downloading…",
                                 value: 76,
                                 total: 100)
                    .progressViewStyle(.linear)
                }
                VStack {
                    Text("Circular style:")
                    Spacer()
                    ProgressView("Downloading…",
                                 value: 76,
                                 total: 100)
                    .progressViewStyle(.circular)
                }
            }
        }
    }
    private var gauges: some View {
        GroupBox {
            VStack(alignment: .leading) {
                // https://developer.apple.com/documentation/swiftui/gaugestyle
                Text("Styling gauges")
                    .fontWeight(.heavy)
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("Automatic style:")
                    Spacer()
                    Gauge(value: 0.6) {
                        Text("Level")
                    }
                    .gaugeStyle(.automatic)
                }
                VStack(alignment: .leading) {
                    Text("Accessory Circular style:")
                    Spacer()
                    Gauge(value: 0.75) {
                        Text("Level")
                    } currentValueLabel: {
                        Text("0.75")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("1")
                    }
                    .gaugeStyle(.accessoryCircular)
                    
                    // level of clouds today :D
                    Gauge(value: 0.6) {
                        Image(systemName: "cloud")
                    }
                    .gaugeStyle(.accessoryCircular)
                    
                    Gauge(value: 45, in: 0...100) {
                        Label("Sun", systemImage: "sunrise.circle")
                    } currentValueLabel: {
                        Text(45.formatted())
                    } minimumValueLabel: {
                        Image(systemName: "sun.min")
                            .foregroundColor(.gray)
                    } maximumValueLabel: {
                        Image(systemName: "sun.max")
                            .foregroundColor(.orange)
                    }
                    .tint(Color("Medium", bundle: .module))
                    .labelStyle(.iconOnly)
                    .gaugeStyle(.accessoryCircular)
                }
                VStack(alignment: .leading) {
                    Text("accessoryCircularCapacity style:")
                    Spacer()
                    Gauge(value: 0.6) {
                        Text("Level")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
                VStack(alignment: .leading) {
                    Text("linearCapacity style:")
                    Spacer()
                    Gauge(value: 0.6) {
                        Text("Level")
                    }
                    .gaugeStyle(.linearCapacity)
                }
                VStack(alignment: .leading) {
                    Text("accessoryLinearCapacity style:")
                    Spacer()
                    Gauge(value: 0.6) {
                        Text("Level")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                }
            }
        }
        // end indicators
    }
    
}

#Preview {
    
        StylesView()
    
}

// MARK: - HASHABLE

extension StylesView {
    
    static func == (lhs: StylesView, rhs: StylesView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}



